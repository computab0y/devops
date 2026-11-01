"""Poll s3://<bucket>/submission/, validate each file, and write the outcome to notification/.

For each submitted file <name>:
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


def notify(name, kind, body):
    key = f"{NOTIFICATION}{name}.{kind}.json"
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


def process(obj):
    key = obj["Key"]
    name = key[len(SUBMISSION):]
    size = obj["Size"]
    received = now().isoformat()
    notify(name, "ack", {"file": name, "status": "RECEIVED", "size": size, "received_at": received})

    # Oversized files are rejected on size alone, without downloading them
    if size > MAX_BYTES:
        data, reason = b"", f"file is {size} bytes, limit is {MAX_BYTES}"
    else:
        data = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
        reason = validate(name, data)

    stamp = now().strftime("%Y%m%dT%H%M%SZ")
    dest = f"{'rejected' if reason else 'processed'}/{stamp}/{name}"
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
    notify(name, "rejected" if reason else "accepted", result)
    log.info("%s %s%s", result["status"], name, f" ({reason})" if reason else "")


def pending():
    cutoff = now() - datetime.timedelta(seconds=SETTLE_SECONDS)
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix=SUBMISSION):
        for obj in page.get("Contents", []):
            name = obj["Key"][len(SUBMISSION):]
            base = os.path.basename(name)
            if not name or name.endswith("/") or base.startswith(".") or base.endswith(IGNORED_SUFFIXES):
                continue
            if obj["LastModified"] > cutoff:
                continue  # still settling
            yield obj


def main():
    log.info("watching s3://%s/%s every %ss", BUCKET, SUBMISSION, POLL_SECONDS)
    while True:
        try:
            for obj in pending():
                try:
                    process(obj)
                except Exception:
                    log.exception("failed to process %s", obj["Key"])
        except Exception:
            log.exception("poll failed")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
