<#
.SYNOPSIS
  Log in to the file gateway over SFTP as every password user and check their folders.

.DESCRIPTION
  For each "username,password" line in the credentials file, logs in with WinSCP and checks that:
    - the session opens at / (the user's chroot, /users/ftp_root/<username> on the server)
    - / holds exactly two folders, SUBMISSION and NOTIFICATION, and the user can't go above it
    - each folder holds DO_NOT_DELETE.txt containing a date

  Then, unless -SkipServerCheck is given, uses `oc exec` (needs `oc login`) to check from the
  server side that /users/ftp_root/<username>/SUBMISSION and NOTIFICATION exist for every user.

  Needs WinSCP (its .NET assembly, WinSCPnet.dll, ships with it). Exit code 0 if every check passed.

.EXAMPLE
  .\test-users.ps1
  .\test-users.ps1 -Quiet
  .\test-users.ps1 -CredsFile D:\secure\users.csv -SkipServerCheck
  # if scripts are blocked: powershell -ExecutionPolicy Bypass -File .\test-users.ps1
#>
[CmdletBinding()]
param(
  [string]$CredsFile = $(if ($env:FILEGW_CREDS) { $env:FILEGW_CREDS } else { Join-Path $HOME '.filegw\users.csv' }),
  [string]$HostName = $(if ($env:FILEGW_HOST) { $env:FILEGW_HOST } else { '62.84.179.61' }),
  [int]$Port = $(if ($env:FILEGW_PORT) { [int]$env:FILEGW_PORT } else { 30022 }),
  [string]$WinSCPPath,
  [switch]$Quiet,
  [switch]$SkipServerCheck
)
$ErrorActionPreference = 'Stop'

# Pinned host key (the same one as in connect/known_hosts), so a stranger on this address is refused
$HostKey = 'ssh-ed25519 255 Pi+mQFEyqmZxEZ0yobpmvcHe2N4UgWAkbImjHIOVjdQ'
$Folders = @('NOTIFICATION', 'SUBMISSION')
$Marker = 'DO_NOT_DELETE.txt'
$FtpRoot = '/users/ftp_root'
# Output of the Linux `date` command, e.g. "Wed Nov 25 22:40:01 UTC 2026"
$DatePattern = '^[A-Z][a-z]{2} [A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}:\d{2} [A-Za-z0-9+-]+ \d{4}$'

# --- WinSCP .NET assembly ---
$dirs = @($WinSCPPath,
  (Join-Path $env:LOCALAPPDATA 'Programs\WinSCP'),
  (Join-Path ${env:ProgramFiles(x86)} 'WinSCP'),
  (Join-Path $env:ProgramFiles 'WinSCP')) |
  Where-Object { $_ -and (Test-Path (Join-Path $_ 'WinSCPnet.dll')) }
if (-not $dirs) { throw 'WinSCPnet.dll not found. Install WinSCP, or pass -WinSCPPath <folder that holds WinSCPnet.dll>.' }
Add-Type -Path (Join-Path @($dirs)[0] 'WinSCPnet.dll')

# --- Credentials: "username,password" lines ---
if (-not (Test-Path $CredsFile)) { throw "Cannot read credentials file: $CredsFile" }
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

function Get-Names($session, $path) {
  @($session.ListDirectory($path).Files | Where-Object { $_.Name -ne '.' -and $_.Name -ne '..' })
}

# Returns a list of problems for one user (empty = pass); appends listing lines to $details
function Test-User($u, $details, $tmp) {
  $problems = New-Object System.Collections.Generic.List[string]
  $opts = New-Object WinSCP.SessionOptions -Property @{
    Protocol              = [WinSCP.Protocol]::Sftp
    HostName              = $HostName
    PortNumber            = $Port
    UserName              = $u.User
    Password              = $u.Password
    SshHostKeyFingerprint = $HostKey
    Timeout               = New-TimeSpan -Seconds 20
  }
  $session = New-Object WinSCP.Session
  try {
    try { $session.Open($opts) } catch { $problems.Add("login failed: $(Get-ErrorText $_)"); return ,$problems }

    if ($session.HomePath -ne '/') { $problems.Add("opened at '$($session.HomePath)', expected /") }

    $root = Get-Names $session '/'
    $names = @($root | ForEach-Object { $_.Name } | Sort-Object)
    $details.Add("/: $($names -join ', ')")
    if (($names -join ',') -ne ($Folders -join ',')) {
      $problems.Add("/ holds [$($names -join ', ')], expected only [$($Folders -join ', ')]")
    }
    foreach ($f in $root) { if (-not $f.IsDirectory) { $problems.Add("/$($f.Name) is not a folder") } }

    # Locked in: the parent of / must be / itself
    $up = @(Get-Names $session '/..' | ForEach-Object { $_.Name } | Sort-Object)
    if (($up -join ',') -ne ($names -join ',')) { $problems.Add("can see above its home: /.. holds [$($up -join ', ')]") }

    foreach ($d in $Folders) {
      if ($names -notcontains $d) { continue }
      $remote = "/$d/$Marker"
      if (-not $session.FileExists($remote)) { $problems.Add("$remote missing"); continue }
      $local = Join-Path $tmp "$($u.User)-$d.txt"
      $session.GetFileToDirectory($remote, $tmp) | Out-Null
      Move-Item -Force (Join-Path $tmp $Marker) $local
      $text = (Get-Content -Raw $local).Trim()
      $details.Add("$remote`: $text")
      if ($text -notmatch $DatePattern) { $problems.Add("$remote doesn't contain a date: '$text'") }
    }
  } catch {
    $problems.Add("error: $(Get-ErrorText $_)")
  } finally {
    $session.Dispose()
  }
  return ,$problems
}

# --- Server side: /users/ftp_root/<user>/{SUBMISSION,NOTIFICATION} ---
$serverDirs = $null
if (-not $SkipServerCheck) {
  if (-not (Get-Command oc -ErrorAction SilentlyContinue)) {
    Write-Warning 'oc not found - skipping the server-side check (or pass -SkipServerCheck)'
  } else {
    $out = & oc exec -n filegateway deploy/filegw-gateway -c gateway -- sh -c "cd $FtpRoot && ls -d */SUBMISSION */NOTIFICATION" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "server-side check failed (is 'oc login' current?): $($out -join ' ')"
    } else {
      $serverDirs = @{}
      foreach ($line in $out) { $serverDirs["$line".Trim()] = $true }
    }
  }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("filegw-test-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
$failed = New-Object System.Collections.Generic.List[string]
try {
  foreach ($u in $users) {
    $details = New-Object System.Collections.Generic.List[string]
    $problems = Test-User $u $details $tmp
    if ($null -ne $serverDirs) {
      foreach ($d in $Folders) {
        if (-not $serverDirs.ContainsKey("$($u.User)/$d")) { $problems.Add("server: $FtpRoot/$($u.User)/$d missing") }
      }
      if ($problems.Count -eq 0) { $details.Insert(0, "server: $FtpRoot/$($u.User)/{SUBMISSION,NOTIFICATION} exist") }
    }
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
if ($null -eq $serverDirs -and -not $SkipServerCheck) { Write-Host 'Server-side check was skipped (see warning above).' -ForegroundColor Yellow }
if ($failed.Count -gt 0) { Write-Host "Failed: $($failed -join ' ')"; exit 1 }
exit 0
