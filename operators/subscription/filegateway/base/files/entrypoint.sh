#!/bin/sh
# Mount each S3 folder with rclone (FUSE) under each SFTP user's home, then run sshd.
# `df -h` in an SSH session shows the mapping, e.g. "s3://filegateway/submission  ...  /home/ray/submission".
#
# ray (SFTP_USER) maps to the bucket root: s3://<bucket>/{submission,notification}
# Users in the filegw-users secret map by name: s3://<bucket>/<user>/{submission,notification}
set -eu

U="${SFTP_USER:-ray}"
H="/home/$U"
USERS_FILE=/users/users
MOUNTED_USERS=/run/filegw-users   # read by healthcheck.sh; a later secret change can't fail the probe

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

# mount_home USER HOME S3_PREFIX  (S3_PREFIX is "" or "<user>/")
mount_home() {
  m_user="$1"; m_home="$2"; m_prefix="$3"
  m_uid="$(id -u "$m_user")"
  m_gid="$(id -g "$m_user")"
  for d in submission notification; do
    mkdir -p "$m_home/$d"
    chown "$m_uid:$m_gid" "$m_home/$d"
    ro=""
    [ "$d" = notification ] && ro="--read-only"
    rclone mount "s3:${BUCKET_NAME}/${m_prefix}$d" "$m_home/$d" $ro \
      --devname "s3://${BUCKET_NAME}/${m_prefix}$d" \
      --daemon --allow-other \
      --uid "$m_uid" --gid "$m_gid" --umask 022 \
      --vfs-cache-mode writes --cache-dir "/cache/${m_prefix}$d" \
      --dir-cache-time 5s --attr-timeout 1s \
      --log-file "/var/log/rclone-$m_user-$d.log" --log-level INFO </dev/null
    echo "mounted s3:${BUCKET_NAME}/${m_prefix}$d -> $m_home/$d"
  done
}

: > "$MOUNTED_USERS"
mount_home "$U" "$H" ""
echo "$U" >> "$MOUNTED_USERS"

# Additional SFTP-only users: one "name:sha512-crypt-hash" per line
if [ -r "$USERS_FILE" ]; then
  getent group filegw-users >/dev/null || groupadd -g 1999 filegw-users
  uid=2000
  while IFS=: read -r name hash; do
    [ -n "$name" ] || continue
    uid=$((uid + 1))
    case "$name" in
      root|"$U"|submission|notification|processed|rejected|*[!a-z0-9_-]*)
        echo "WARNING: skipping invalid or reserved username '$name'"; continue ;;
    esac
    id "$name" >/dev/null 2>&1 ||
      useradd -M -d "/home/$name" -s /usr/sbin/nologin -u "$uid" -G filegw-users -p "$hash" "$name"
    # sshd's ChrootDirectory requires a root-owned home that only root can write to
    mkdir -p "/home/$name"
    chown root:root "/home/$name"
    chmod 755 "/home/$name"
    mount_home "$name" "/home/$name" "$name/"
    echo "$name" >> "$MOUNTED_USERS"
  done < "$USERS_FILE"
fi

exec /usr/sbin/sshd -D -e
