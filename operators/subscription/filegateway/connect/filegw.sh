#!/usr/bin/env bash
# Connect to the file gateway from macOS/Linux.
#
#   ./filegw.sh ssh                 interactive shell (run `df -h` to see the S3 mapping)
#   ./filegw.sh sftp                interactive SFTP session
#   ./filegw.sh put FILE...         upload files into submission/
#   ./filegw.sh s3 [aws s3 ARGS]    use the whole bucket with the AWS CLI (needs `oc login`)
#                                   default: ls s3://filegateway/ --recursive
#
# Env overrides: FILEGW_KEY (private key, default ~/.ssh/contabo_okd),
#                FILEGW_HOST (default 62.84.179.61), FILEGW_PORT (default 30022), FILEGW_USER (default ray)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="${FILEGW_KEY:-$HOME/.ssh/contabo_okd}"
HOST="${FILEGW_HOST:-62.84.179.61}"
PORT="${FILEGW_PORT:-30022}"
USER_="${FILEGW_USER:-ray}"
BUCKET=filegateway

# Pinned host keys from the repo, so a new PC verifies the server instead of trusting on first use
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o UserKnownHostsFile="$HERE/known_hosts" -o StrictHostKeyChecking=yes
          -o ConnectTimeout=10 -o ServerAliveInterval=30)

need_key() {
  [ -f "$KEY" ] || { echo "Private key not found: $KEY (copy it from your Mac, or set FILEGW_KEY)" >&2; exit 1; }
  chmod 600 "$KEY" 2>/dev/null || true
}

s3() {
  command -v oc >/dev/null || { echo "oc CLI not found" >&2; exit 1; }
  command -v aws >/dev/null || { echo "AWS CLI not found (brew install awscli)" >&2; exit 1; }
  oc whoami >/dev/null 2>&1 || { echo "Not logged in: oc login --server=https://api.okd.funky-bash.com:6443" >&2; exit 1; }

  AWS_ACCESS_KEY_ID="$(oc get secret "$BUCKET" -n filegateway -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)"
  AWS_SECRET_ACCESS_KEY="$(oc get secret "$BUCKET" -n filegateway -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION=us-east-1

  local lport=18080
  oc port-forward -n rook-ceph svc/rook-ceph-rgw-objectstore "$lport:8080" >/dev/null 2>&1 &
  trap "kill $! 2>/dev/null" EXIT
  for _ in $(seq 1 30); do nc -z localhost "$lport" 2>/dev/null && break; sleep 0.5; done

  if [ $# -eq 0 ]; then set -- ls "s3://$BUCKET/" --recursive; fi
  aws --endpoint-url "http://localhost:$lport" s3 "$@"
}

case "${1:-}" in
  ssh)  need_key; shift; exec ssh "${SSH_OPTS[@]}" -p "$PORT" "$USER_@$HOST" "$@" ;;
  sftp) need_key; exec sftp "${SSH_OPTS[@]}" -P "$PORT" "$USER_@$HOST" ;;
  put)
    need_key; shift
    [ $# -gt 0 ] || { echo "usage: $0 put FILE..." >&2; exit 1; }
    batch="cd submission"$'\n'
    for f in "$@"; do batch+="put \"$f\""$'\n'; done
    sftp "${SSH_OPTS[@]}" -P "$PORT" -b - "$USER_@$HOST" <<<"$batch"
    ;;
  s3)   shift; s3 "$@" ;;
  *)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
