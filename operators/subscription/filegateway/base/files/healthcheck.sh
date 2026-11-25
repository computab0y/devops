#!/bin/sh
# Liveness: every S3 folder mounted at startup must still be mounted.
while IFS= read -r d; do
  mountpoint -q "$d" || { echo "not mounted: $d"; exit 1; }
done < /run/filegw-mounts
