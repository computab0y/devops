#!/bin/sh
# Mount each S3 folder with rclone (FUSE) under each SFTP user's home, then run sshd.
# `df -h` in an SSH session shows the mapping, e.g. "s3://filegateway/submission  ...  /home/ray/submission".
#
# ray (SFTP_USER) maps to the bucket root:      /home/ray/{submission,notification} -> s3://<bucket>/{submission,notification}
# Users in the filegw-users secret are chrooted: /users/ftp_root/<user>/{SUBMISSION,NOTIFICATION}
#                                                -> s3://<bucket>/<user>/{submission,notification}
set -eu

U="${SFTP_USER:-ray}"
H="/home/$U"
USERS_FILE=/etc/filegw/users
FTP_ROOT=/users/ftp_root
MOUNTS=/run/filegw-mounts   # every mountpoint, read by healthcheck.sh
MARKER=DO_NOT_DELETE.txt

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
# The bucket already exists; without this, uploads first try to create it and Ceph refuses (TooManyBuckets)
export RCLONE_CONFIG_S3_NO_CHECK_BUCKET=true

# mount_dir USER LOCAL_DIR S3_PATH [--read-only]   (S3_PATH is relative to the bucket)
mount_dir() {
  m_user="$1"; m_dir="$2"; m_s3="$3"; m_ro="${4:-}"
  m_uid="$(id -u "$m_user")"
  m_gid="$(id -g "$m_user")"
  mkdir -p "$m_dir"
  chown "$m_uid:$m_gid" "$m_dir"
  rclone mount "s3:${BUCKET_NAME}/$m_s3" "$m_dir" $m_ro \
    --devname "s3://${BUCKET_NAME}/$m_s3" \
    --daemon --allow-other \
    --uid "$m_uid" --gid "$m_gid" --umask 022 \
    --vfs-cache-mode writes --cache-dir "/cache/$m_s3" \
    --dir-cache-time 5s --attr-timeout 1s \
    --log-file "/var/log/rclone-$m_user-$(basename "$m_dir").log" --log-level INFO </dev/null
  echo "$m_dir" >> "$MOUNTS"
  echo "mounted s3:${BUCKET_NAME}/$m_s3 -> $m_dir"
}

# ensure_marker S3_PATH: create S3_PATH/DO_NOT_DELETE.txt holding the current date, if it's missing
ensure_marker() {
  if [ -z "$(rclone lsf --files-only --include "/$MARKER" "s3:${BUCKET_NAME}/$1/")" ]; then
    date | rclone rcat "s3:${BUCKET_NAME}/$1/$MARKER"
    echo "created s3:${BUCKET_NAME}/$1/$MARKER"
  fi
}

: > "$MOUNTS"
mount_dir "$U" "$H/submission" submission
mount_dir "$U" "$H/notification" notification --read-only

# Additional SFTP-only users: one "name:sha512-crypt-hash" per line
if [ -r "$USERS_FILE" ]; then
  getent group filegw-users >/dev/null || groupadd -g 1999 filegw-users
  # sshd's ChrootDirectory requires every directory down to the user's home to be root-owned
  # and writable only by root, so users can only write inside SUBMISSION
  mkdir -p "$FTP_ROOT"
  chown root:root /users "$FTP_ROOT"
  chmod 755 /users "$FTP_ROOT"
  uid=2000
  while IFS=: read -r name hash; do
    [ -n "$name" ] || continue
    uid=$((uid + 1))
    case "$name" in
      root|"$U"|submission|notification|processed|rejected|*[!a-z0-9_-]*)
        echo "WARNING: skipping invalid or reserved username '$name'"; continue ;;
    esac
    home="$FTP_ROOT/$name"
    id "$name" >/dev/null 2>&1 ||
      useradd -M -d "$home" -s /usr/sbin/nologin -u "$uid" -G filegw-users -p "$hash" "$name"
    mkdir -p "$home"
    chown root:root "$home"
    chmod 755 "$home"
    ensure_marker "$name/submission"
    ensure_marker "$name/notification"
    mount_dir "$name" "$home/SUBMISSION" "$name/submission"
    mount_dir "$name" "$home/NOTIFICATION" "$name/notification" --read-only
  done < "$USERS_FILE"
fi

exec /usr/sbin/sshd -D -e
