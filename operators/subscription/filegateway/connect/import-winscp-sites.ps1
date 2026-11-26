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

  Also caches the server's ssh-ed25519 host key in WinSCP, taken from the pinned known_hosts
  next to this script, so a new PC trusts the right server without a prompt (and WinSCP.com
  scripts don't fail with "Host key wasn't verified" / "Authentication failed"). If WinSCP
  already caches a different key for the server, it is left alone with a warning unless -Force.

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

# --- Host key: cache the pinned ssh-ed25519 key from known_hosts in WinSCP ---
# WinSCP (like PuTTY) stores an ed25519 key as "0x<x>,0x<y>": the curve point's coordinates in hex.
# known_hosts holds the 32-byte public key, which is y plus the sign of x, so recover x (RFC 8032 5.1.3).
Add-Type -AssemblyName System.Numerics
function ConvertTo-WinSCPEd25519Key([string]$base64) {
  $blob = [Convert]::FromBase64String($base64)
  $u32 = { param([int]$o) ([int]$blob[$o] -shl 24) -bor ([int]$blob[$o + 1] -shl 16) -bor ([int]$blob[$o + 2] -shl 8) -bor [int]$blob[$o + 3] }
  $o = 4 + (& $u32 0)                                  # skip the "ssh-ed25519" name
  if ((& $u32 $o) -ne 32) { throw 'known_hosts ssh-ed25519 entry is not a 32-byte key' }
  [byte[]]$pk = $blob[($o + 4)..($o + 35)]
  $sign = $pk[31] -shr 7
  $pk[31] = $pk[31] -band 0x7F
  $p = [System.Numerics.BigInteger]::Pow(2, 255) - 19
  $mod = { param($a) $r = $a % $p; if ($r.Sign -lt 0) { $r + $p } else { $r } }
  $pow = { param($b, $e) [System.Numerics.BigInteger]::ModPow($b, $e, $p) }
  $y = New-Object System.Numerics.BigInteger (,[byte[]]($pk + [byte]0))   # little-endian, positive
  $d = & $mod ([System.Numerics.BigInteger](-121665) * (& $pow 121666 ($p - 2)))
  $u = & $mod ($y * $y - 1)
  $v = & $mod ($d * $y * $y + 1)
  $x = & $mod ($u * (& $pow $v 3) * (& $pow (& $mod ($u * (& $pow $v 7))) ([System.Numerics.BigInteger]::Divide($p - 5, 8))))
  if (-not (& $mod ($v * $x * $x - $u)).IsZero) { $x = & $mod ($x * (& $pow 2 ([System.Numerics.BigInteger]::Divide($p - 1, 4)))) }
  if (-not (& $mod ($v * $x * $x - $u)).IsZero) { throw 'known_hosts ssh-ed25519 entry is not a valid key' }
  if ([int](-not $x.IsEven) -ne $sign) { $x = $p - $x }
  $hex = { param($n) $h = $n.ToString('x').TrimStart('0'); if ($h) { $h } else { '0' } }
  '0x{0},0x{1}' -f (& $hex $x), (& $hex $y)
}

$hostKeyStatus = ''
$knownHosts = Join-Path $PSScriptRoot 'known_hosts'
$khHost = if ($Port -eq 22) { $HostName } else { "[$HostName]:$Port" }
$pinned = if (Test-Path $knownHosts) {
  Get-Content $knownHosts | ForEach-Object { , ($_.Trim() -split '\s+') } |
    Where-Object { $_.Count -ge 3 -and $_[1] -eq 'ssh-ed25519' -and (($_[0] -split ',') -contains $khHost) } |
    Select-Object -First 1
}
if (-not $pinned) {
  Write-Warning "No ssh-ed25519 key for $khHost in $knownHosts; WinSCP will ask you to accept the server's key on first connect."
} else {
  $cacheValue = ConvertTo-WinSCPEd25519Key $pinned[2]
  $cacheName = "ssh-ed25519@$Port`:$HostName"
  $hk = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Martin Prikryl\WinSCP 2\SshHostKeys')
  try {
    $cached = $hk.GetValue($cacheName)
    if ($cached -eq $cacheValue) {
      $hostKeyStatus = 'Host key already cached in WinSCP (matches known_hosts).'
    } elseif ($cached -and -not $Force) {
      Write-Warning ("WinSCP caches a different ssh-ed25519 key for $HostName`:$Port than known_hosts. Either the server's " +
        'key changed or WinSCP trusted the wrong server. Left as is; check, then re-run with -Force to replace it.')
      $hostKeyStatus = 'Host key NOT updated (different key cached; see warning).'
    } else {
      $hk.SetValue($cacheName, $cacheValue, 'String')
      $hostKeyStatus = if ($cached) { 'Host key in WinSCP replaced with the one from known_hosts.' } else { 'Host key from known_hosts cached in WinSCP.' }
    }
  } finally { $hk.Close() }
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
if ($hostKeyStatus) { Write-Host $hostKeyStatus }
if (-not $NoPasswords) { Write-Host 'Passwords are saved with WinSCP''s obfuscation only; set a master password in WinSCP > Preferences > Security to encrypt them.' }
