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

Password users (user01, user02, ...) get their own `SUBMISSION` and `NOTIFICATION` folders instead.
See [Password users](#password-users).

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

## Password users

Each user in the `filegw-users` secret logs in over SFTP with a password and is locked into
`/users/ftp_root/<user>` on the gateway. They see it as `/`, holding only two folders:

| User sees | Bucket folder | |
|---|---|---|
| `/SUBMISSION` | `s3://filegateway/<user>/submission/` | uploads go here |
| `/NOTIFICATION` | `s3://filegateway/<user>/notification/` | read-only |

Each folder holds a `DO_NOT_DELETE.txt` containing the date it was created. The gateway creates
any that are missing when it starts, and the processor ignores them. The processor handles each
user's uploads the same way as `ray`'s, under the `<user>/` prefix.

```bash
scripts/provision-users.sh 30                                  # user01..user30; keeps existing passwords
oc apply -k base                                               # first time only
oc rollout restart deployment/filegw-gateway -n filegateway    # load user changes
connect/test-logins.sh                                         # log in as each user and list directories
connect/test-logins.sh -q /path/to/users.csv                   # PASS/FAIL only, other credentials file
```

Plaintext passwords are only in `~/.filegw/users.csv` (`username,password` lines, readable only by
you). The cluster stores SHA-512 crypt hashes. Allow about 60Mi of gateway memory per user. On
Windows, run `provision-users.sh` from WSL with `FILEGW_CREDS=/mnt/c/Users/<you>/.filegw/users.csv`
so the Windows scripts below find the file.

### Windows: test users and add them to WinSCP

These need WinSCP installed and read `%USERPROFILE%\.filegw\users.csv`. Run them from
`connect\` in PowerShell. Close WinSCP before importing, or it may overwrite the new sites.

```powershell
powershell -ExecutionPolicy Bypass -File .\test-users.ps1          # log in as each user and check folders and files
powershell -ExecutionPolicy Bypass -File .\import-winscp-sites.ps1  # add a WinSCP site per user, in folder FileGateway
powershell -ExecutionPolicy Bypass -File .\test-winscp-sites.ps1    # log in through each saved WinSCP site
```

- `test-users.ps1` works against any SFTP file gateway (this one, or e.g. a Red Hat Linux server)
  and needs no `oc login`. It asks for the server IP and port, or pass `-HostName` / `-Port`, and
  checks each user is locked into `/users/ftp_root/<user>` (seen as `/`) holding only `SUBMISSION`
  and `NOTIFICATION`. A server not pinned in `known_hosts` shows its host key for you to confirm first;
  pass `-HostKey` to skip that. For this gateway add `-CheckMarker` to also check `DO_NOT_DELETE.txt`;
  `-TestWrite` proves each user can upload; `-Quiet` prints PASS/FAIL only.
- `import-winscp-sites.ps1` saves passwords in WinSCP's own format, which only obfuscates them.
  Use `-NoPasswords` to be asked at login instead, or set a master password in WinSCP (Preferences >
  Security). Existing sites are kept unless you pass `-Force`, for example after new passwords.

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

Image digests are pinned in the `images:` block of `base/kustomization.yaml`, so applying never
changes which build is running. A new build still rolls out on its own through the image trigger,
but the next `oc apply -k` would roll it back. After each build, copy the new digest from
`oc get istag -n filegateway` into `kustomization.yaml` and commit it.

Always apply via `-k`: the namespace comes from `kustomization.yaml`, so `oc apply -f` on a
single file lands in whatever project you're in.

**Host keys** live only in the `filegw-hostkeys` secret (see `base/kustomization.yaml` for the
command to recreate it). If you rebuild the cluster and generate new ones, update
`connect/known_hosts` and the fingerprints above, or every client will refuse to connect.

## Security notes

- Internet-facing on NodePort 30022: `ray` is key-only; password users are SFTP-only and chrooted
  to their own home. No TCP/agent/X11 forwarding, `MaxAuthTries 3`.
- The gateway pod is privileged (required for FUSE) and isolated in its own namespace with no
  service-account token mounted. S3 credentials are only in root's environment inside the pod,
  not the SSH user's session.
