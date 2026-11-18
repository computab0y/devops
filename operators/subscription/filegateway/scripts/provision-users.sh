#!/usr/bin/env bash
# Create or update the gateway's password users.
#
#   ./provision-users.sh [COUNT]     default COUNT: 30 (user01..user30)
#
# Plaintext credentials stay on this machine in $FILEGW_CREDS (default ~/.filegw/users.csv, mode 600).
# Existing passwords are kept, so re-running only adds missing users. The cluster only gets
# SHA-512 crypt hashes, in the filegw-users secret. Restart the gateway afterwards to load changes:
#   oc rollout restart deployment/filegw-gateway -n filegateway
set -euo pipefail
umask 077

COUNT="${1:-30}"
PREFIX="${FILEGW_USER_PREFIX:-user}"
CREDS="${FILEGW_CREDS:-$HOME/.filegw/users.csv}"
NS=filegateway

command -v oc >/dev/null || { echo "oc CLI not found" >&2; exit 1; }
oc whoami >/dev/null 2>&1 || { echo "Not logged in: oc login --server=https://api.okd.funky-bash.com:6443" >&2; exit 1; }
printf 'x' | openssl passwd -6 -stdin >/dev/null 2>&1 || { echo "openssl with SHA-512 crypt support is required" >&2; exit 1; }

mkdir -p "$(dirname "$CREDS")"
[ -f "$CREDS" ] || echo "username,password" > "$CREDS"
chmod 600 "$CREDS"

for i in $(seq 1 "$COUNT"); do
  user="$(printf '%s%02d' "$PREFIX" "$i")"
  grep -q "^$user," "$CREDS" && continue
  password="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-28)"
  echo "$user,$password" >> "$CREDS"
done

hashes="$(mktemp)"
trap 'rm -f "$hashes"' EXIT
tail -n +2 "$CREDS" | while IFS=, read -r user password; do
  [ -n "$user" ] || continue
  printf '%s:%s\n' "$user" "$(printf '%s' "$password" | openssl passwd -6 -stdin)"
done > "$hashes"

oc create secret generic filegw-users -n "$NS" --from-file=users="$hashes" --dry-run=client -o yaml | oc apply -f -
echo "$(wc -l < "$hashes" | tr -d ' ') users in secret $NS/filegw-users; credentials in $CREDS"
