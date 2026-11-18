#!/bin/sh
# Mount each S3 folder with rclone (FUSE) under the SFTP user's home, then run sshd.
# `df -h` in an SSH session shows the mapping, e.g. "s3://filegateway/submission  ...  /home/ray/submission".
set -eu

U="${SFTP_USER:-ray}"
H="/home/$U"
UID_="$(id -u "$U")"
GID_="$(id -g "$U")"

# Stable host keys from the filegw-hostkeys secret, else generate ephemeral ones
if ls /hostkeys/ssh_host_*_key >/dev/null 2>&1; then
  cp /hostkeys/ssh_host_* /etc/ssh/
  chmod 600 /etc/ssh/ssh_host_*_key
else
  echo "WARNING: no filegw-hostkeys secret - generating ephemeral host keys"
  ssh-keygen -A
fi
cp /config/sshd_config /etc/ssh/sshd_config

mkdir -p "$H/.ssh"
cp /config/authorized_keys "$H/.ssh/authorized_keys"
chown -R "$U:$U" "$H/.ssh"
chmod 700 "$H/.ssh"
chmod 600 "$H/.ssh/authorized_keys"

# rclone remote "s3" -> in-cluster Ceph RGW (credentials stay in root's env, not the user's session)
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER=Ceph
export RCLONE_CONFIG_S3_ENDPOINT="http://${BUCKET_HOST}:${BUCKET_PORT}"
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_S3_FORCE_PATH_STYLE=true

for d in submission notification; do
  mkdir -p "$H/$d"
  chown "$U:$U" "$H/$d"
  ro=""
  [ "$d" = notification ] && ro="--read-only"
  rclone mount "s3:${BUCKET_NAME}/$d" "$H/$d" $ro \
    --devname "s3://${BUCKET_NAME}/$d" \
    --daemon --allow-other \
    --uid "$UID_" --gid "$GID_" --umask 022 \
    --vfs-cache-mode writes --cache-dir "/cache/$d" \
    --dir-cache-time 5s --attr-timeout 1s \
    --log-file "/var/log/rclone-$d.log" --log-level INFO
  echo "mounted s3:${BUCKET_NAME}/$d -> $H/$d"
done

exec /usr/sbin/sshd -D -e
