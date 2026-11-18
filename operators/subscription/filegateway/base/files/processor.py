"""Poll each user's submission/ folder, validate each file, and write the outcome to notification/.

The original user's folders are at the bucket root; every other user's are under <username>/.
All paths below are relative to that root. For each submitted file <name>:
  notification/<name>.ack.json                      written as soon as the file is picked up
  notification/<name>.accepted.json | .rejected.json  written after validation
The file is then moved to processed/<timestamp>/<name> or rejected/<timestamp>/<name>.
"""
import csv
import datetime
import hashlib
import io
import json
import logging
import os
import time

import boto3
from botocore.config import Config

BUCKET = os.environ["BUCKET_NAME"]
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "10"))
SETTLE_SECONDS = int(os.environ.get("SETTLE_SECONDS", "5"))
MAX_BYTES = int(os.environ.get("MAX_BYTES", str(100 * 1024 * 1024)))
ALLOWED = {e.strip().lower() for e in os.environ.get("ALLOWED_EXTENSIONS", ".csv,.txt,.json,.xml,.pdf").split(",")}
IGNORED_SUFFIXES = (".filepart", ".part", ".tmp", "~")  # in-progress uploads from WinSCP and friends

SUBMISSION, NOTIFICATION = "submission/", "notification/"
RESERVED_PREFIXES = {SUBMISSION, NOTIFICATION, "processed/", "rejected/"}

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("filegw-processor")

s3 = boto3.client(
    "s3",
    endpoint_url=f"http://{os.environ['BUCKET_HOST']}:{os.environ['BUCKET_PORT']}",
    aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
    region_name="us-east-1",
    config=Config(s3={"addressing_style": "path"}),
)


def now():
    return datetime.datetime.now(datetime.timezone.utc)


def notify(root, name, kind, body):
    key = f"{root}{NOTIFICATION}{name}.{kind}.json"
    s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(body, indent=2).encode(), ContentType="application/json")
    log.info("wrote %s", key)


def validate(name, data):
    """Return None if accepted, else the rejection reason."""
    ext = os.path.splitext(name)[1].lower()
    if len(data) == 0:
        return "file is empty"
    if ext not in ALLOWED:
        return f"extension '{ext or '(none)'}' not allowed; allowed: {', '.join(sorted(ALLOWED))}"
    if ext in (".csv", ".json", ".txt", ".xml"):
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError as e:
            return f"not valid UTF-8 text: {e}"
        if ext == ".csv":
            rows = [r for r in csv.reader(io.StringIO(text)) if r]
            if not rows:
                return "CSV has no rows"
            widths = {len(r) for r in rows}
            if len(widths) > 1:
                return f"CSV rows have inconsistent column counts: {sorted(widths)}"
        elif ext == ".json":
            try:
                json.loads(text)
            except json.JSONDecodeError as e:
                return f"invalid JSON: {e}"
    if ext == ".pdf" and not data.startswith(b"%PDF-"):
        return "file does not look like a PDF (missing %PDF- header)"
    return None


def process(obj, root):
    key = obj["Key"]
    name = key[len(root + SUBMISSION):]
    size = obj["Size"]
    received = now().isoformat()
    notify(root, name, "ack", {"file": name, "status": "RECEIVED", "size": size, "received_at": received})

    # Oversized files are rejected on size alone, without downloading them
    if size > MAX_BYTES:
        data, reason = b"", f"file is {size} bytes, limit is {MAX_BYTES}"
    else:
        data = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
        reason = validate(name, data)

    stamp = now().strftime("%Y%m%dT%H%M%SZ")
    dest = f"{root}{'rejected' if reason else 'processed'}/{stamp}/{name}"
    s3.copy_object(Bucket=BUCKET, Key=dest, CopySource={"Bucket": BUCKET, "Key": key})
    s3.delete_object(Bucket=BUCKET, Key=key)

    result = {
        "file": name,
        "status": "REJECTED" if reason else "ACCEPTED",
        "size": size,
        "etag": obj.get("ETag", "").strip('"'),
        "received_at": received,
        "processed_at": now().isoformat(),
        "archived_to": f"s3://{BUCKET}/{dest}",
    }
    if data:
        result["sha256"] = hashlib.sha256(data).hexdigest()
    if reason:
        result["reason"] = reason
    notify(root, name, "rejected" if reason else "accepted", result)
    log.info("%s %s%s%s", result["status"], root, name, f" ({reason})" if reason else "")


def roots():
    """Return the bucket root plus one '<username>/' prefix per user folder."""
    found = [""]
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Delimiter="/"):
        found += [p["Prefix"] for p in page.get("CommonPrefixes", []) if p["Prefix"] not in RESERVED_PREFIXES]
    return found


def pending(root):
    cutoff = now() - datetime.timedelta(seconds=SETTLE_SECONDS)
    prefix = root + SUBMISSION
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            name = obj["Key"][len(prefix):]
            base = os.path.basename(name)
            if not name or name.endswith("/") or base.startswith(".") or base.endswith(IGNORED_SUFFIXES):
                continue
            if obj["LastModified"] > cutoff:
                continue  # still settling
            yield obj


def main():
    log.info("watching s3://%s/[<user>/]%s every %ss", BUCKET, SUBMISSION, POLL_SECONDS)
    while True:
        try:
            for root in roots():
                for obj in pending(root):
                    try:
                        process(obj, root)
                    except Exception:
                        log.exception("failed to process %s", obj["Key"])
        except Exception:
            log.exception("poll failed")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
