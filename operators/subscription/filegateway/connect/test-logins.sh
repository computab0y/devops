#!/usr/bin/env bash
# Log in to the file gateway as each user in a credentials file and list their directories.
#
#   ./test-logins.sh [-q] [CREDENTIALS_FILE]
#
#   -q                 print only PASS/FAIL per user, not the directory listings
#   CREDENTIALS_FILE   "username,password" lines (default: $FILEGW_CREDS or ~/.filegw/users.csv)
#
# Env overrides: FILEGW_HOST (default 62.84.179.61), FILEGW_PORT (default 30022)
# Exit status: 0 if every user passed, 1 otherwise. Needs only the OpenSSH client (8.4 or newer).
set -uo pipefail

QUIET=0
if [ "${1:-}" = "-q" ]; then QUIET=1; shift; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS="${1:-${FILEGW_CREDS:-$HOME/.filegw/users.csv}}"
HOST="${FILEGW_HOST:-62.84.179.61}"
PORT="${FILEGW_PORT:-30022}"

[ -r "$CREDS" ] || { echo "Cannot read credentials file: $CREDS" >&2; exit 2; }

# The password reaches sftp through an askpass helper, so it never appears in a process list
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ASKPASS="$WORK/askpass"
printf '#!/bin/sh\nprintf "%%s\\n" "$FILEGW_TEST_PASSWORD"\n' > "$ASKPASS"
chmod 700 "$ASKPASS"

passed=0
failed=0
failures=""

while IFS= read -r line <&3 || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in ''|'#'*|username,*) continue ;; esac
  user="${line%%,*}"
  password="${line#*,}"

  output="$(printf 'ls -la /\nls -la /submission\nls -la /notification\n' |
    FILEGW_TEST_PASSWORD="$password" SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
    sftp -F /dev/null -P "$PORT" \
      -o UserKnownHostsFile="$HERE/known_hosts" -o StrictHostKeyChecking=yes \
      -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o NumberOfPasswordPrompts=1 -o ConnectTimeout=15 -o LogLevel=ERROR \
      "$user@$HOST" 2>&1)"
  rc=$?

  reason=""
  if [ "$rc" -ne 0 ]; then
    reason="login failed (sftp exit $rc)"
  elif printf '%s\n' "$output" | grep -qE "^(Can't ls|Couldn't|remote .*: )|not found"; then
    reason="directory listing failed"
  elif ! printf '%s\n' "$output" | grep -qE ' /submission$' || ! printf '%s\n' "$output" | grep -qE ' /notification$'; then
    reason="submission/notification missing"
  fi

  if [ -z "$reason" ]; then
    passed=$((passed + 1))
    echo "PASS  $user"
    [ "$QUIET" -eq 1 ] || printf '%s\n' "$output" | sed 's/^/      /'
  else
    failed=$((failed + 1))
    failures="$failures $user"
    echo "FAIL  $user: $reason"
    printf '%s\n' "$output" | sed 's/^/      /'
  fi
done 3< "$CREDS"

echo
echo "$passed passed, $failed failed (of $((passed + failed))) against $HOST:$PORT"
[ "$failed" -eq 0 ] || { echo "Failed:$failures"; exit 1; }
