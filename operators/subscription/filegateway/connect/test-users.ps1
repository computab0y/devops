<#
.SYNOPSIS
  Log in to a file gateway server over SFTP as every password user and check their folders.

.DESCRIPTION
  Works against any SFTP server (e.g. a Red Hat Linux file gateway); it needs no OpenShift/oc
  login. Asks for the server's IP/hostname and port first, unless -HostName is given.

  For each "username,password" line in the credentials file, logs in with WinSCP and checks that:
    - the user is locked into their folder: the session opens at /, which is the sshd
      ChrootDirectory /users/ftp_root/<username> on the server, and /.. shows nothing more
    - / holds exactly two folders, SUBMISSION and NOTIFICATION, and the user can open both
  A user who logs in anywhere else (e.g. /home/<user>, seeing the whole server) fails.

  Server identity: the host key is taken from -HostKey, else from connect\known_hosts for that
  host:port, else fetched from the server and shown for you to confirm before any password is
  sent. The script then prints the -HostKey value to pass for unattended runs.

  -CheckMarker also requires each folder to hold DO_NOT_DELETE.txt containing a date.
  -TestWrite uploads and deletes a small file in SUBMISSION to prove the user can upload there
  (NOTIFICATION is only read by users, and is read-only on the OKD gateway, so it isn't written).
  The file is named .filegw-write-test-<user>-SUBMISSION.tmp and deleted straight away; the OKD
  gateway's processor ignores hidden and .tmp files, but check that anything else watching
  SUBMISSION on your server does too before using it.

  Needs WinSCP (its .NET assembly, WinSCPnet.dll, ships with it). Exit code 0 if every check passed.

.EXAMPLE
  .\test-users.ps1                                    # asks for the server IP and port
  .\test-users.ps1 -HostName 10.20.30.40              # port 22
  .\test-users.ps1 -HostName 10.20.30.40 -Port 2222 -TestWrite -Quiet
  .\test-users.ps1 -HostName 10.20.30.40 -HostKey "ssh-ed25519 255 AbC...=" -CredsFile D:\secure\users.csv
  .\test-users.ps1 -HostName 62.84.179.61 -Port 30022 -CheckMarker   # the OKD gateway
  # if scripts are blocked: powershell -ExecutionPolicy Bypass -File .\test-users.ps1
#>
[CmdletBinding()]
param(
  [string]$HostName,
  [int]$Port = 0,
  [string]$HostKey,
  [string]$CredsFile = $(if ($env:FILEGW_CREDS) { $env:FILEGW_CREDS } else { Join-Path $HOME '.filegw\users.csv' }),
  [string]$FtpRoot = '/users/ftp_root',
  [string]$WinSCPPath,
  [switch]$CheckMarker,
  [switch]$TestWrite,
  [switch]$Quiet,
  # Pause between logins, so fail2ban / sshd MaxStartups on the server don't block this PC
  [int]$DelayMs = 500
)
$ErrorActionPreference = 'Stop'

$Folders = @('NOTIFICATION', 'SUBMISSION')
$WriteFolders = @('SUBMISSION')   # users upload here; NOTIFICATION is the server's replies (read-only for users)
$Marker = 'DO_NOT_DELETE.txt'
# Output of the Linux `date` command, e.g. "Wed Nov 25 22:40:01 UTC 2026"
$DatePattern = '^[A-Z][a-z]{2} [A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}:\d{2} [A-Za-z0-9+-]+ \d{4}$'

# --- Server to test: from the parameters, else ask ---
if (-not $HostName) {
  $HostName = (Read-Host 'File gateway server IP or hostname').Trim()
  if (-not $HostName) { throw 'No server given.' }
  if (-not $Port) {
    $answer = (Read-Host 'SSH/SFTP port [22]').Trim()
    if ($answer) { $Port = [int]$answer }
  }
}
if (-not $Port) { $Port = 22 }

# --- WinSCP .NET assembly ---
$dirs = @($WinSCPPath,
  (Join-Path $env:LOCALAPPDATA 'Programs\WinSCP'),
  (Join-Path ${env:ProgramFiles(x86)} 'WinSCP'),
  (Join-Path $env:ProgramFiles 'WinSCP')) |
  Where-Object { $_ -and (Test-Path (Join-Path $_ 'WinSCPnet.dll')) }
if (-not $dirs) { throw 'WinSCPnet.dll not found. Install WinSCP, or pass -WinSCPPath <folder that holds WinSCPnet.dll>.' }
Add-Type -Path (Join-Path @($dirs)[0] 'WinSCPnet.dll')

# --- Credentials: "username,password" lines ---
if (-not (Test-Path $CredsFile)) { throw "Cannot read credentials file: $CredsFile (or pass -CredsFile <path>)" }
$users = @(Get-Content $CredsFile | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('username,') -and $_.Contains(',') } |
  ForEach-Object {
    $i = $_.IndexOf(',')
    [pscustomobject]@{ User = $_.Substring(0, $i); Password = $_.Substring($i + 1) }
  })
if ($users.Count -eq 0) { throw "No users in $CredsFile" }

function Get-ErrorText($err) {
  $e = $err.Exception
  while ($e.InnerException) { $e = $e.InnerException }
  ($e.Message -split "`r?`n" | Where-Object { $_ }) -join ' '
}

# --- Host key: -HostKey, else pinned in known_hosts, else fetch and ask ---
# WinSCP wants "<type> <bits> <SHA-256 base64 without padding>"; known_hosts holds the whole key.
function Get-PinnedHostKey {
  $file = Join-Path $PSScriptRoot 'known_hosts'
  if (-not (Test-Path $file)) { return $null }
  $name = if ($Port -eq 22) { $HostName } else { "[$HostName]:$Port" }
  $bits = @{ 'ssh-ed25519' = 255; 'ssh-ed448' = 448 }
  foreach ($line in Get-Content $file) {
    $f = $line.Trim() -split '\s+'
    if ($f.Count -lt 3 -or (($f[0] -split ',') -notcontains $name)) { continue }
    if (-not $bits.ContainsKey($f[1])) { continue }      # prefer a fixed-size key type; others: use -HostKey
    $sha = [Security.Cryptography.SHA256]::Create().ComputeHash([Convert]::FromBase64String($f[2]))
    return "$($f[1]) $($bits[$f[1]]) $([Convert]::ToBase64String($sha).TrimEnd('='))"
  }
  $null
}

$baseOpts = @{
  Protocol   = [WinSCP.Protocol]::Sftp
  HostName   = $HostName
  PortNumber = $Port
  Timeout    = New-TimeSpan -Seconds 20
}
if (-not $HostKey) {
  $HostKey = Get-PinnedHostKey
  if ($HostKey) {
    Write-Host "Host key for ${HostName}:$Port pinned in known_hosts: $HostKey"
  } else {
    $scan = New-Object WinSCP.Session
    try { $HostKey = $scan.ScanFingerprint((New-Object WinSCP.SessionOptions -Property $baseOpts), 'SHA-256') }
    catch { throw "Cannot reach ${HostName}:$Port - $(Get-ErrorText $_)" }
    finally { $scan.Dispose() }
    Write-Host ''
    Write-Host "Server ${HostName}:$Port presents host key:"
    Write-Host "  $HostKey" -ForegroundColor Cyan
    Write-Host 'Check it on the server before trusting it:  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
    if ((Read-Host 'Is this the right server? Passwords are only sent if you answer y [y/N]') -notmatch '^[yY]') { exit 1 }
    Write-Host "Next time, skip this question with:  -HostKey `"$HostKey`""
  }
}
$baseOpts.SshHostKeyFingerprint = $HostKey

# Returns a list of problems for one user (empty = pass); appends listing lines to $details
function Test-User($u, $details, $tmp) {
  $problems = New-Object System.Collections.Generic.List[string]
  $opts = New-Object WinSCP.SessionOptions -Property $baseOpts
  $opts.UserName = $u.User
  $opts.Password = $u.Password
  $session = New-Object WinSCP.Session
  try {
    try { $session.Open($opts) } catch { $problems.Add("login failed: $(Get-ErrorText $_)"); return ,$problems }

    # Locked in: the session must open at / (the chroot, /users/ftp_root/<user> on the server)
    $real = "$($FtpRoot.TrimEnd('/'))/$($u.User)"
    if ($session.HomePath -ne '/') {
      $why = if ($session.FileExists($real)) { "; it can see $real, so the whole server is visible" } else { '' }
      $problems.Add("NOT locked in: opened at '$($session.HomePath)', expected / (sshd ChrootDirectory $real)$why")
      return ,$problems
    }
    $details.Add("home: / (locked in; / is $real on the server)")

    $root = @($session.ListDirectory('/').Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' })
    $names = @($root | ForEach-Object { $_.Name } | Sort-Object)
    $details.Add("/: $($names -join ', ')")
    if (($names -join ',') -ne ($Folders -join ',')) {
      $problems.Add("/ holds [$($names -join ', ')], expected only [$($Folders -join ', ')]")
    }

    # The parent of / must be / itself, or the user can climb out
    $up = @($session.ListDirectory('/..').Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' } |
      ForEach-Object { $_.Name } | Sort-Object)
    if (($up -join ',') -ne ($names -join ',')) { $problems.Add("can see above its folder: /.. holds [$($up -join ', ')]") }

    foreach ($d in $Folders) {
      $dir = "/$d"
      if (-not $session.FileExists($dir)) { $problems.Add("$dir missing"); continue }
      if (-not $session.GetFileInfo($dir).IsDirectory) { $problems.Add("$dir is not a folder"); continue }
      try { $session.ListDirectory($dir) | Out-Null } catch { $problems.Add("${dir}: can't open ($(Get-ErrorText $_))"); continue }

      if ($CheckMarker) {
        $remote = "$dir/$Marker"
        if (-not $session.FileExists($remote)) { $problems.Add("$remote missing") }
        else {
          $local = Join-Path $tmp "$($u.User)-$d.txt"
          $session.GetFileToDirectory($remote, $tmp) | Out-Null
          Move-Item -Force (Join-Path $tmp $Marker) $local
          $text = (Get-Content -Raw $local).Trim()
          $details.Add("$remote`: $text")
          if ($text -notmatch $DatePattern) { $problems.Add("$remote doesn't contain a date: '$text'") }
        }
      }

      if ($TestWrite -and $WriteFolders -contains $d) {
        $probe = Join-Path $tmp ".filegw-write-test-$($u.User)-$d.tmp"
        Set-Content -Path $probe -Value 'write test' -Encoding ASCII
        $remote = "$dir/$(Split-Path -Leaf $probe)"
        try {
          $session.PutFileToDirectory($probe, $dir) | Out-Null
          $session.RemoveFile($remote) | Out-Null
          $details.Add("${dir}: writable")
        } catch {
          $problems.Add("${dir}: can't write ($(Get-ErrorText $_))")
        } finally {
          Remove-Item $probe -ErrorAction SilentlyContinue
        }
      }
    }
  } catch {
    $problems.Add("error: $(Get-ErrorText $_)")
  } finally {
    $session.Dispose()
  }
  return ,$problems
}

Write-Host "Testing $($users.Count) users from $CredsFile against ${HostName}:$Port"
Write-Host ''
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("filegw-test-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
$failed = New-Object System.Collections.Generic.List[string]
try {
  $n = 0
  foreach ($u in $users) {
    if ($n++ -gt 0 -and $DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    $details = New-Object System.Collections.Generic.List[string]
    $problems = Test-User $u $details $tmp
    if ($problems.Count -eq 0) {
      Write-Host ("PASS  {0}" -f $u.User) -ForegroundColor Green
      if (-not $Quiet) { $details | ForEach-Object { Write-Host "      $_" } }
    } else {
      $failed.Add($u.User)
      Write-Host ("FAIL  {0}" -f $u.User) -ForegroundColor Red
      $problems | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
      if (-not $Quiet) { $details | ForEach-Object { Write-Host "      $_" } }
    }
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$passed = $users.Count - $failed.Count
Write-Host ''
Write-Host "$passed passed, $($failed.Count) failed (of $($users.Count)) against ${HostName}:$Port"
if ($failed.Count -gt 0) { Write-Host "Failed: $($failed -join ' ')"; exit 1 }
exit 0
