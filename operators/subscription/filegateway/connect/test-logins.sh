#!/usr/bin/env bash
# Log in to one or more file gateways as each user in a credentials file and list their directories.
# Results are shown on screen and saved to a log file.
#
#   Several gateways:  ./test-logins.sh [-q] [-o LOG_FILE] -g GATEWAYS_FILE
#   One gateway:       ./test-logins.sh [-q] [-o LOG_FILE] [-H HOST] [-p PORT] [-k KNOWN_HOSTS] [CREDENTIALS_FILE]
#
#   -h, --help         show the usage and exit
#   -q                 print only PASS/FAIL per user, not the directory listings
#   -g GATEWAYS_FILE   test every gateway listed in this file (format below)
#   -H HOST            address of the gateway to test
#   -p PORT            SFTP port of the gateway (default: 22)
#   -k KNOWN_HOSTS     file holding the gateway's trusted host key
#                      (default: known_hosts in the same folder as this script)
#   -o LOG_FILE        where to save the results
#                      (default: ~/.filegw/logs/test-logins-YYYYMMDD-HHMMSS.log)
#   CREDENTIALS_FILE   "username,password" lines
#
# There is no default gateway or credentials file. Anything missing is asked for at the
# terminal. When the script can't ask, such as in a scheduled job, it shows the usage and
# exits with status 2.
#
# Exit status: 0 if every user passed, 1 if any user or gateway failed, 2 if the test could
# not start. Needs only the OpenSSH client (8.4 or newer).
#
# HOW IT WORKS
#
#   1. Read the options and ask for anything missing.
#   2. Create a small temporary "askpass" helper that hands each password to sftp.
#   3. For each gateway, check that its settings are usable and its host key is trusted.
#   4. For each user on that gateway, open one SFTP session and run:
#        ls -l /               the user's top-level folders
#        ls -l /submission     files waiting to be processed
#        ls -l /notification   processing results
#   5. Mark the user PASS or FAIL (see below) and carry on with the next user.
#   6. Print a summary, save everything to the log and exit with the overall result.
#
# WHAT COUNTS AS A PASS
#
#   A user passes only if all of these are true:
#     - sftp connected, the server's host key matched and the password was accepted
#     - none of the three listings reported an error
#     - the top-level listing contains both /submission and /notification
#
#   A failure is reported as one of:
#     login failed (sftp exit N)       wrong password, unknown user or server unreachable
#     directory listing failed         logged in, but a folder could not be listed
#     submission/notification missing  logged in, but an expected folder is not there
#
#   With -g, each gateway is summarised as one of:
#     PASS    every user passed
#     FAIL    at least one user failed
#     ERROR   the gateway could not be tested, such as an untrusted host key or missing file
#
# GATEWAYS FILE FORMAT
#
#   One gateway per line (see gateways.example.csv):
#     name,host,port,credentials_file,known_hosts_file
#
#   port defaults to 22 if blank. known_hosts_file is optional and defaults to known_hosts in
#   the same folder as this script. Relative paths are relative to the gateways file. Blank
#   lines, lines starting with # and the header line above are skipped.
#
# CREDENTIALS FILE FORMAT
#
#   One "username,password" per line. Blank lines, lines starting with # and a
#   "username,password" header line are skipped. Passwords may contain commas.
#
# SECURITY
#
#   Passwords are never passed on a command line or written to the log. The log and
#   temporary files are readable only by the current user, and the temporary files are
#   removed when the script exits.

# -u: treat unset variables as errors. -o pipefail: a pipeline fails if any command in it fails.
# -e is deliberately not set, so one user's failed login doesn't stop the remaining tests.
set -uo pipefail

# New files are created readable and writable by the current user only
umask 077

# --- Options and settings ---

usage() {
  cat <<EOF
Test file gateway logins: sign in as each user and list their directories.

Usage:
  Several gateways:  $(basename "$0") [-q] [-o LOG_FILE] -g GATEWAYS_FILE
  One gateway:       $(basename "$0") [-q] [-o LOG_FILE] [-H HOST] [-p PORT] [-k KNOWN_HOSTS] [CREDENTIALS_FILE]

Arguments:
  CREDENTIALS_FILE  File of "username,password" lines. Asked for if omitted.

Options:
  -h, --help        Show this help and exit.
  -q                Show only PASS/FAIL for users who pass, without directory listings.
  -g GATEWAYS_FILE  Test every gateway in this file. Each line is:
                    name,host,port,credentials_file,known_hosts_file
  -H HOST           Gateway address. Asked for if omitted.
  -p PORT           Gateway SFTP port. Default: 22.
  -k KNOWN_HOSTS    File holding the gateway's trusted host key.
                    Default: known_hosts in the same folder as this script.
  -o LOG_FILE       Save the results to LOG_FILE.
                    Default: ~/.filegw/logs/test-logins-YYYYMMDD-HHMMSS.log

Exit status:
  0  every user passed
  1  at least one user or gateway failed
  2  the test could not start

Examples:
  $(basename "$0") -g gateways.csv
  $(basename "$0") -q -g gateways.csv
  $(basename "$0") -H gateway.example.com -p 2222 -k gateway_known_hosts /path/to/users.csv
EOF
}

valid_host() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; }
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }

# Remove spaces from both ends of a value
trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# Expand a leading ~ and make a relative path relative to the folder given as $2
resolve_path() {
  local path="${1/#\~/$HOME}"
  case "$path" in
    /*) printf '%s' "$path" ;;
    *)  printf '%s/%s' "$2" "$path" ;;
  esac
}

# getopts can't read long options, so --help is handled here
for arg in "$@"; do
  if [ "$arg" = "--help" ]; then usage; exit 0; fi
done

# Remember whether the script was run with no arguments, to decide when to show the usage
NO_ARGS=0
[ "$#" -eq 0 ] && NO_ARGS=1

QUIET=0
LOG=""
GATEWAYS=""
HOST=""
PORT=""
KNOWN_HOSTS=""
while getopts "hqg:H:p:k:o:" opt; do
  case "$opt" in
    h) usage; exit 0 ;;
    q) QUIET=1 ;;
    g) GATEWAYS="$OPTARG" ;;
    H) HOST="$OPTARG" ;;
    p) PORT="$OPTARG" ;;
    k) KNOWN_HOSTS="$OPTARG" ;;
    o) LOG="$OPTARG" ;;
    # Unknown option or missing value: getopts has printed the error, so add the usage
    *) echo >&2; usage >&2; exit 2 ;;
  esac
done
# Remove the options, leaving the optional credentials file as $1
shift $((OPTIND - 1))

if [ "$#" -gt 1 ]; then
  echo "Too many arguments: expected one credentials file." >&2
  echo >&2
  usage >&2
  exit 2
fi

# A gateways file holds each gateway's settings, so they can't also be given as options
if [ -n "$GATEWAYS" ] && { [ -n "$HOST$PORT$KNOWN_HOSTS" ] || [ "$#" -eq 1 ]; }; then
  echo "-g can't be combined with -H, -p, -k or a credentials file." >&2
  echo >&2
  usage >&2
  exit 2
fi

# The folder holding this script, which is also where the default known_hosts is kept
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_KNOWN_HOSTS="$HERE/known_hosts"
CREDS="${1:-}"

# With no terminal to ask at, such as a scheduled job, everything must be given as arguments
if [ -z "$GATEWAYS" ] && { [ -z "$HOST" ] || [ -z "$CREDS" ]; } && [ ! -t 0 ]; then
  echo "Give a gateways file (-g), or a gateway address (-H) and a credentials file." >&2
  echo >&2
  usage >&2
  exit 2
fi

if [ "$NO_ARGS" -eq 1 ]; then usage; echo; fi

# Ask for anything missing, repeating until the answer is usable. Ctrl-C or Ctrl-D cancels.
if [ -z "$GATEWAYS" ] && [ -z "$HOST" ] && [ -z "$CREDS" ]; then
  while :; do
    read -r -p "Gateways file (press Enter to test one gateway): " GATEWAYS || { echo; exit 2; }
    GATEWAYS="${GATEWAYS/#\~/$HOME}"
    if [ -z "$GATEWAYS" ] || { [ -f "$GATEWAYS" ] && [ -r "$GATEWAYS" ]; }; then break; fi
    echo "Cannot read gateways file: $GATEWAYS" >&2
  done
fi

if [ -z "$GATEWAYS" ]; then
  if [ -z "$HOST" ]; then
    while :; do
      read -r -p "Gateway address: " HOST || { echo; exit 2; }
      if valid_host "$HOST"; then break; fi
      echo "Enter a hostname or IP address." >&2
    done
    while [ -z "$PORT" ]; do
      read -r -p "Gateway port [22]: " PORT || { echo; exit 2; }
      PORT="${PORT:-22}"
      if ! valid_port "$PORT"; then echo "Enter a port from 1 to 65535." >&2; PORT=""; fi
    done
  fi
  while [ -z "$CREDS" ]; do
    read -r -p "Credentials file: " CREDS || { echo; exit 2; }
    # The shell doesn't expand a typed ~, so replace it with the home folder
    CREDS="${CREDS/#\~/$HOME}"
    if [ -z "$CREDS" ]; then
      echo "Enter the path to the credentials file." >&2
    elif [ ! -f "$CREDS" ] || [ ! -r "$CREDS" ]; then
      echo "Cannot read credentials file: $CREDS" >&2
      CREDS=""
    fi
  done
  PORT="${PORT:-22}"
  KNOWN_HOSTS="${KNOWN_HOSTS:-$DEFAULT_KNOWN_HOSTS}"
fi

# --- Gateway checks ---

# Checks the current HOST, PORT, CREDS and KNOWN_HOSTS. On failure, sets GATEWAY_ERROR.
# Each gateway has its own host key, so an untrusted one is caught here rather than being
# reported as a failed login for every user. known_hosts omits the port when it is 22.
check_gateway() {
  local entry
  GATEWAY_ERROR=""
  HOST_KEY_MISSING=0
  if [ "$PORT" = 22 ]; then entry="$HOST"; else entry="[$HOST]:$PORT"; fi

  if ! valid_host "$HOST"; then
    GATEWAY_ERROR="Invalid gateway address: $HOST"
  elif ! valid_port "$PORT"; then
    GATEWAY_ERROR="Invalid gateway port: $PORT"
  elif [ ! -f "$CREDS" ] || [ ! -r "$CREDS" ]; then
    GATEWAY_ERROR="Cannot read credentials file: $CREDS"
  elif ! ssh-keygen -F "$entry" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
    GATEWAY_ERROR="No trusted host key for $entry in: $KNOWN_HOSTS"
    HOST_KEY_MISSING=1
  fi
  [ -z "$GATEWAY_ERROR" ]
}

# Explains how to trust the current gateway's host key
host_key_help() {
  cat <<EOF

Save the gateway's host key, check its fingerprint with the gateway's administrator,
then point this script at the saved file:

  ssh-keyscan -p $PORT $HOST > gateway_known_hosts
  ssh-keygen -lf gateway_known_hosts
EOF
}

# With one gateway, stop now if it can't be tested
if [ -z "$GATEWAYS" ] && ! check_gateway; then
  echo "$GATEWAY_ERROR" >&2
  if [ "$HOST_KEY_MISSING" -eq 1 ]; then host_key_help >&2; fi
  exit 2
fi

# With several gateways, load the list now so a missing or empty file stops the run
GATEWAY_LINES=()
if [ -n "$GATEWAYS" ]; then
  if [ ! -f "$GATEWAYS" ] || [ ! -r "$GATEWAYS" ]; then
    echo "Cannot read gateways file: $GATEWAYS" >&2
    exit 2
  fi
  GATEWAYS_DIR="$(cd "$(dirname "$GATEWAYS")" && pwd)"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(trim "${line%$'\r'}")"
    case "$line" in ''|'#'*|name,host,*) continue ;; esac
    GATEWAY_LINES+=("$line")
  done < "$GATEWAYS"
  if [ "${#GATEWAY_LINES[@]}" -eq 0 ]; then
    echo "No gateways found in: $GATEWAYS" >&2
    exit 2
  fi
fi

LOG="${LOG:-$HOME/.filegw/logs/test-logins-$(date +%Y%m%d-%H%M%S).log}"
mkdir -p "$(dirname "$LOG")" && : > "$LOG" || { echo "Cannot write log file: $LOG" >&2; exit 2; }

# --- Password helper ---

# sftp normally asks for a password at the keyboard. When SSH_ASKPASS is set, it runs that
# program instead and reads the password from its output. This helper prints the password
# held in FILEGW_TEST_PASSWORD, which is set only for the sftp command below.
#
# The password reaches sftp through an askpass helper, so it never appears in a process list
WORK="$(mktemp -d)"
# Delete the helper however the script ends
trap 'rm -rf "$WORK"' EXIT
ASKPASS="$WORK/askpass"
printf '#!/bin/sh\nprintf "%%s\\n" "$FILEGW_TEST_PASSWORD"\n' > "$ASKPASS"
chmod 700 "$ASKPASS"

# --- The test ---

# Tests every user on the current gateway. Returns 0 if they all passed, 1 if any failed and
# 2 if the credentials file has no users. Leaves the counts in RESULT_PASSED and RESULT_FAILED.
run_tests() {
  local line user password output rc reason failures=""
  RESULT_PASSED=0
  RESULT_FAILED=0

  echo "Server: $HOST:$PORT"
  echo "Credentials: $CREDS"
  echo

  # The credentials file is read through file descriptor 3 (opened at the end of this loop),
  # so commands inside the loop can't accidentally consume its lines from standard input.
  # The "|| [ -n "$line" ]" also handles a last line with no newline at the end.
  while IFS= read -r line <&3 || [ -n "$line" ]; do
    # Remove the carriage return left by files saved on Windows
    line="${line%$'\r'}"
    # Skip blank lines, comments and the header
    case "$line" in ''|'#'*|username,*) continue ;; esac
    # Split at the first comma only, so a password can contain commas
    user="${line%%,*}"
    password="${line#*,}"

    # Send the listing commands to sftp on standard input and capture everything it prints.
    # sftp's -b (batch) option can't be used here because it disables password logins.
    #
    #   SSH_ASKPASS_REQUIRE=force          always get the password from the helper
    #   -F /dev/null                       ignore personal settings in ~/.ssh/config
    #   UserKnownHostsFile, StrictHost...  refuse a server that doesn't match the trusted host key
    #   PreferredAuthentications=password  test the password, never an SSH key
    #   PubkeyAuthentication=no            as above
    #   NumberOfPasswordPrompts=1          fail straight away on a wrong password
    #   ConnectTimeout=15                  give up on an unreachable server after 15 seconds
    #   LogLevel=ERROR                     hide banners and warnings
    #   --                                 never treat a username from the file as an sftp option
    output="$(printf 'ls -l /\nls -l /submission\nls -l /notification\n' |
      FILEGW_TEST_PASSWORD="$password" SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
      sftp -F /dev/null -P "$PORT" \
        -o UserKnownHostsFile="$KNOWN_HOSTS" -o StrictHostKeyChecking=yes \
        -o PreferredAuthentications=password -o PubkeyAuthentication=no \
        -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 -o LogLevel=ERROR \
        -- "$user@$HOST" 2>&1)"
    rc=$?

    # Work out the result. Without -b, sftp still exits 0 when a listing fails after a
    # successful login, so the output has to be checked as well as the exit code.
    reason=""
    if [ "$rc" -ne 0 ]; then
      reason="login failed (sftp exit $rc)"
    elif printf '%s\n' "$output" | grep -qE "^(Can't ls|Couldn't|remote .*: )|not found"; then
      reason="directory listing failed"
    elif ! printf '%s\n' "$output" | grep -qE ' /submission$' || ! printf '%s\n' "$output" | grep -qE ' /notification$'; then
      reason="submission/notification missing"
    fi

    # Report the result. Failures always show sftp's output, even with -q, to help diagnose them.
    if [ -z "$reason" ]; then
      RESULT_PASSED=$((RESULT_PASSED + 1))
      echo "PASS  $user"
      [ "$QUIET" -eq 1 ] || printf '%s\n' "$output" | sed 's/^/      /'
    else
      RESULT_FAILED=$((RESULT_FAILED + 1))
      failures="$failures $user"
      echo "FAIL  $user: $reason"
      printf '%s\n' "$output" | sed 's/^/      /'
    fi
  done 3< "$CREDS"

  # An empty file must not look like a successful test
  if [ $((RESULT_PASSED + RESULT_FAILED)) -eq 0 ]; then
    echo "No users found in: $CREDS"
    return 2
  fi

  # Summary, with the names of any users who failed
  echo
  echo "$RESULT_PASSED passed, $RESULT_FAILED failed (of $((RESULT_PASSED + RESULT_FAILED))) against $HOST:$PORT"
  [ "$RESULT_FAILED" -eq 0 ] || { echo "Failed:$failures"; return 1; }
}

# Tests one gateway with the settings already chosen
run_single() {
  echo "File gateway login test: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  run_tests
}

# Tests every gateway in the gateways file, then prints one summary line for each.
# A gateway that can't be tested is recorded as an ERROR and the run moves on to the next.
run_gateways() {
  local total="${#GATEWAY_LINES[@]}" number=0 overall=0 line name creds known extra rc status detail summary=""

  echo "File gateway login test: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Gateways: $GATEWAYS ($total)"

  for line in "${GATEWAY_LINES[@]}"; do
    number=$((number + 1))
    IFS=, read -r name HOST PORT creds known extra <<< "$line"
    name="$(trim "$name")"; HOST="$(trim "$HOST")"; PORT="$(trim "$PORT")"
    creds="$(trim "$creds")"; known="$(trim "$known")"
    PORT="${PORT:-22}"

    echo
    echo "=== Gateway $number of $total: $name ==="

    if [ -z "$name" ] || [ -z "$HOST" ] || [ -z "$creds" ] || [ -n "$extra" ]; then
      status=ERROR
      detail="Invalid line: expected name,host,port,credentials_file,known_hosts_file"
      echo "$detail"
    else
      CREDS="$(resolve_path "$creds" "$GATEWAYS_DIR")"
      if [ -n "$known" ]; then
        KNOWN_HOSTS="$(resolve_path "$known" "$GATEWAYS_DIR")"
      else
        KNOWN_HOSTS="$DEFAULT_KNOWN_HOSTS"
      fi

      if ! check_gateway; then
        status=ERROR
        detail="$GATEWAY_ERROR"
        echo "$detail"
        if [ "$HOST_KEY_MISSING" -eq 1 ]; then host_key_help; fi
      else
        run_tests
        rc=$?
        detail="$RESULT_PASSED passed, $RESULT_FAILED failed"
        case "$rc" in
          0) status=PASS ;;
          1) status=FAIL ;;
          *) status=ERROR; detail="No users found in: $CREDS" ;;
        esac
      fi
    fi

    [ "$status" = PASS ] || overall=1
    summary="$summary$(printf '%-6s %-16s %-28s %s' "$status" "$name" "$HOST:$PORT" "$detail")"$'\n'
  done

  echo
  echo "=== Summary ==="
  printf '%s' "$summary"
  return "$overall"
}

# --- Run and save the results ---

# tee shows the results on screen and writes them to the log at the same time.
# PIPESTATUS[0] is the result of the test; $? would only give the result of tee.
if [ -n "$GATEWAYS" ]; then
  run_gateways 2>&1 | tee "$LOG"
else
  run_single 2>&1 | tee "$LOG"
fi
status=${PIPESTATUS[0]}
echo "Results saved to $LOG"
exit "$status"
