# filegateway

SFTP/SSH file gateway on the Contabo OKD cluster, backed by an S3 bucket on the
cluster's own Ceph object store.

```
PuTTY / WinSCP / ssh ──SFTP/SSH 62.84.179.61:30022──▶ filegw-gateway pod (sshd + rclone FUSE)
                                                        ~/submission   ⇄ s3://filegateway/submission/
                                                        ~/notification ⇄ s3://filegateway/notification/  (read-only)
                                                                    │
                                                         Ceph RGW bucket "filegateway"
                                                                    │
                                     filegw-processor pod ── polls submission/ every 10s
                                        writes notification/<file>.ack.json, then .accepted.json or .rejected.json
                                        moves the file to processed/<ts>/ or rejected/<ts>/
```

`df -h` in an SSH session shows which bucket folder each directory is:

```
s3://filegateway/submission    1.0P     0  1.0P   0% /home/ray/submission
s3://filegateway/notification  1.0P     0  1.0P   0% /home/ray/notification
```

(1.0P is what S3 reports; the bucket has a 20G quota in `base/bucket.yaml`.)

## Connecting from another PC

| | |
|---|---|
| Host | `62.84.179.61` |
| Port | `30022` |
| Protocol | SFTP (WinSCP) / SSH (PuTTY, `ssh`) |
| User | `ray` |
| Auth | SSH key only - `contabo_okd` (public half in `base/files/authorized_keys`) |
| Host key | ED25519 `SHA256:Pi+mQFEyqmZxEZ0yobpmvcHe2N4UgWAkbImjHIOVjdQ` |
| | RSA `SHA256:/6gOF00XvstZxntYXU/og76P2AeJjbFFTURGHIqqpAA` |

### 1. Get the private key onto the PC

The private key is **not** in git. Copy `~/.ssh/contabo_okd` from the Mac to the new PC over
something private (USB stick, AirDrop, password manager attachment, `scp`) - never email/chat.

- **macOS/Linux:** put it at `~/.ssh/contabo_okd` and `chmod 600 ~/.ssh/contabo_okd`.
- **Windows:** put it at `C:\Users\<you>\.ssh\contabo_okd`. Windows OpenSSH refuses keys other
  users can read, so lock it down:
  ```powershell
  icacls $HOME\.ssh\contabo_okd /inheritance:r /grant:r "${env:USERNAME}:R"
  ```

Alternatively, generate a separate key on the new PC (`ssh-keygen -t ed25519`), append its `.pub`
line to `base/files/authorized_keys`, and `oc apply -k base` - then each PC can be revoked
on its own.

### 2. Connect

Clone this repo and use the helper in `connect/`. It pins the host keys from
`connect/known_hosts`, so a new PC checks it's talking to the real server instead of trusting
whatever answers on first connect.

**macOS / Linux**
```bash
cd operators/subscription/filegateway/connect
./filegw.sh ssh               # shell - run df -h, ls ~/notification, etc.
./filegw.sh sftp              # interactive sftp
./filegw.sh put a.csv b.json  # upload into submission/
```

Or by hand:
```bash
ssh -i ~/.ssh/contabo_okd -o IdentitiesOnly=yes -p 30022 ray@62.84.179.61
```

**Windows (PowerShell, built-in OpenSSH on Windows 10/11)**
```powershell
cd operators\subscription\filegateway\connect
.\filegw.ps1 ssh
.\filegw.ps1 sftp
.\filegw.ps1 put .\a.csv
# if scripts are blocked: powershell -ExecutionPolicy Bypass -File .\filegw.ps1 ssh
```

**PuTTY / WinSCP**
1. PuTTYgen -> *Load* `contabo_okd` -> *Save private key* as `contabo_okd.ppk`.
2. PuTTY: Host `62.84.179.61`, Port `30022`; *Connection -> Data* user `ray`;
   *Connection -> SSH -> Auth -> Credentials* private key `contabo_okd.ppk`. Save the session.
3. WinSCP: File protocol *SFTP*, Host `62.84.179.61`, Port `30022`, User `ray`;
   *Advanced -> SSH -> Authentication* private key `contabo_okd.ppk`.
4. On first connect, check the fingerprint shown matches the host key above before accepting.

## Using the bucket directly (S3 API)

The bucket is only reachable inside the cluster, and the SFTP login deliberately has no S3
credentials. From any PC with `oc` (logged in) and the AWS CLI:

```bash
./filegw.sh s3                                       # list the whole bucket
./filegw.sh s3 ls s3://filegateway/rejected/ --recursive
./filegw.sh s3 cp s3://filegateway/processed/<ts>/a.csv .
```
(`.\filegw.ps1 s3 ...` on Windows.) It port-forwards the Ceph RGW service to `localhost:18080`,
reads the bucket keys from the `filegateway` secret, runs `aws s3 ...`, then closes the forward.

## Processing rules

Set by env vars on `base/processor.yaml`:

| Var | Default | |
|---|---|---|
| `ALLOWED_EXTENSIONS` | `.csv,.txt,.json,.xml,.pdf` | anything else is rejected |
| `MAX_BYTES` | `104857600` (100MB) | larger files are rejected without downloading |
| `POLL_SECONDS` | `10` | how often `submission/` is scanned |
| `SETTLE_SECONDS` | `5` | ignore objects modified more recently than this |

Also rejected: empty files, non-UTF-8 `.csv/.json/.txt/.xml`, CSVs with inconsistent column
counts, invalid JSON, `.pdf` without a `%PDF-` header. In-progress uploads (`*.filepart`,
`*.part`, `*.tmp`, dotfiles) are skipped. The logic is in `base/files/processor.py`.

Each notification is JSON with the file name, status, size, sha256, timestamps, the rejection
`reason`, and where the original was archived (`archived_to`).

## Deploying

```bash
oc apply -k operators/subscription/filegateway/base
```
The image builds (`filegw-gateway`: Debian 12 + openssh + rclone + fuse3; `filegw-processor`:
python 3.12 + boto3) run in-cluster from the inline Dockerfiles in `base/builds.yaml`. After
changing a Dockerfile: `oc start-build filegw-gateway -n filegateway` - the ConfigChange
trigger only fires on the first build.

Always apply via `-k`: the namespace comes from `kustomization.yaml`, so `oc apply -f` on a
single file lands in whatever project you're in.

**Host keys** live only in the `filegw-hostkeys` secret (see `base/kustomization.yaml` for the
command to recreate it). If you rebuild the cluster and generate new ones, update
`connect/known_hosts` and the fingerprints above, or every client will refuse to connect.

## Security notes

- Internet-facing on NodePort 30022: key-only auth, single non-root user, no TCP/agent/X11
  forwarding, `MaxAuthTries 3`.
- The gateway pod is privileged (required for FUSE) and isolated in its own namespace with no
  service-account token mounted. S3 credentials are only in root's environment inside the pod,
  not the SSH user's session.
