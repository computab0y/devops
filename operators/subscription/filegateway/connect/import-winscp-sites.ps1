<#
.SYNOPSIS
  Add a WinSCP site for every file gateway user, in a site folder (default "FileGateway").

.DESCRIPTION
  Reads "username,password" lines from the credentials file and writes one SFTP site per user to
  WinSCP's registry storage (HKCU\Software\Martin Prikryl\WinSCP 2\Sessions), e.g. FileGateway/user01.
  Close WinSCP first, or it may overwrite the new sites when it exits.

  Passwords are saved in WinSCP's own format, which only obfuscates them. Use -NoPasswords to
  have WinSCP ask at each login instead, or set a master password in WinSCP (Preferences >
  Security) after importing, which encrypts every saved password.

  Existing sites with the same name are left as they are unless -Force is given.
  Then test them all with .\test-winscp-sites.ps1.

.EXAMPLE
  .\import-winscp-sites.ps1
  .\import-winscp-sites.ps1 -Force
  .\import-winscp-sites.ps1 -NoPasswords -Folder "FileGateway (no passwords)"
  # if scripts are blocked: powershell -ExecutionPolicy Bypass -File .\import-winscp-sites.ps1
#>
[CmdletBinding()]
param(
  [string]$CredsFile = $(if ($env:FILEGW_CREDS) { $env:FILEGW_CREDS } else { Join-Path $HOME '.filegw\users.csv' }),
  [string]$HostName = $(if ($env:FILEGW_HOST) { $env:FILEGW_HOST } else { '62.84.179.61' }),
  [int]$Port = $(if ($env:FILEGW_PORT) { [int]$env:FILEGW_PORT } else { 30022 }),
  [string]$Folder = 'FileGateway',
  [switch]$NoPasswords,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'

$SessionsKey = 'Software\Martin Prikryl\WinSCP 2\Sessions'

if (Get-Process WinSCP -ErrorAction SilentlyContinue) {
  Write-Warning 'WinSCP is running. Close it before importing, or it may overwrite the new sites when it exits.'
  if ((Read-Host 'Continue anyway? [y/N]') -notmatch '^[yY]') { exit 1 }
}

$security = Get-ItemProperty 'HKCU:\Software\Martin Prikryl\WinSCP 2\Configuration\Interface' -ErrorAction SilentlyContinue
if (-not $NoPasswords -and $security -and $security.UseMasterPassword) {
  throw 'WinSCP has a master password set, so passwords can''t be imported. Re-run with -NoPasswords.'
}

# WinSCP's password obfuscation for saved sites (the "simple" scheme from its Security.cpp)
$rng = New-Object System.Random
function Protect-WinSCPPassword([string]$password, [string]$key) {
  $magic = 0xA3; $maxLen = 50
  $enc = { param([int]$b) '{0:X2}' -f ((-bnot $b -bxor $magic) -band 0xFF) }
  $bytes = [Text.Encoding]::UTF8.GetBytes($key + $password)
  if ($bytes.Length -gt 255) { throw 'Password too long' }
  $shift = if ($bytes.Length -lt $maxLen) { $rng.Next($maxLen - $bytes.Length) } else { 0 }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append((& $enc 0xFF)).Append((& $enc 0)).Append((& $enc $bytes.Length)).Append((& $enc $shift))
  for ($i = 0; $i -lt $shift; $i++) { [void]$sb.Append((& $enc $rng.Next(256))) }
  foreach ($b in $bytes) { [void]$sb.Append((& $enc $b)) }
  while ($sb.Length -lt $maxLen * 2) { [void]$sb.Append((& $enc $rng.Next(256))) }
  $sb.ToString()
}

# --- Credentials: "username,password" lines ---
if (-not (Test-Path $CredsFile)) { throw "Cannot read credentials file: $CredsFile" }
$users = @(Get-Content $CredsFile | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('username,') -and $_.Contains(',') } |
  ForEach-Object {
    $i = $_.IndexOf(',')
    [pscustomobject]@{ User = $_.Substring(0, $i); Password = $_.Substring($i + 1) }
  })
if ($users.Count -eq 0) { throw "No users in $CredsFile" }

# Site names use / for folders; WinSCP stores them %-escaped in the registry key name
function Get-KeyName([string]$name) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $name.ToCharArray()) {
    if ($c -match '[A-Za-z0-9_.\-/@]') { [void]$sb.Append($c) } else { [void]$sb.Append(('%{0:X2}' -f [int]$c)) }
  }
  $sb.ToString()
}

$root = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SessionsKey)
$added = 0; $updated = 0; $skipped = 0
try {
  foreach ($u in $users) {
    $site = "$Folder/$($u.User)"
    $keyName = Get-KeyName $site
    $exists = $null -ne $root.OpenSubKey($keyName)
    if ($exists -and -not $Force) { Write-Host "skip   $site (already exists; -Force to overwrite)"; $skipped++; continue }
    if ($exists) { $root.DeleteSubKeyTree($keyName) }
    $k = $root.CreateSubKey($keyName)
    try {
      $k.SetValue('HostName', $HostName, 'String')
      $k.SetValue('PortNumber', $Port, 'DWord')
      $k.SetValue('UserName', $u.User, 'String')
      $k.SetValue('FSProtocol', 2, 'DWord')            # SFTP only (the gateway has no SCP)
      $k.SetValue('RemoteDirectory', '/', 'String')
      if (-not $NoPasswords) { $k.SetValue('Password', (Protect-WinSCPPassword $u.Password ($u.User + $HostName)), 'String') }
    } finally { $k.Close() }
    if ($exists) { Write-Host "update $site"; $updated++ } else { Write-Host "add    $site"; $added++ }
  }
} finally { $root.Close() }

Write-Host ''
Write-Host "$added added, $updated updated, $skipped skipped in WinSCP site folder '$Folder' ($HostName`:$Port)"
if (-not $NoPasswords) { Write-Host 'Passwords are saved with WinSCP''s obfuscation only; set a master password in WinSCP > Preferences > Security to encrypt them.' }
