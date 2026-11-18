#!/bin/sh
# Liveness: every S3 folder mounted at startup must still be mounted.
while IFS= read -r u; do
  for d in submission notification; do
    mountpoint -q "/home/$u/$d" || { echo "not mounted: /home/$u/$d"; exit 1; }
  done
done < /run/filegw-users
