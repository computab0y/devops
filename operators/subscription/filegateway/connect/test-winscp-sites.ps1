<#
.SYNOPSIS
  Log in through every saved WinSCP site in a site folder (default "FileGateway") and check it.

.DESCRIPTION
  Uses WinSCP.com with the sites exactly as saved in WinSCP (host, port, username, saved password,
  cached host key), so a PASS means double-clicking that site in WinSCP will work. For each site:
    - the login succeeds and opens at /
    - / holds exactly SUBMISSION and NOTIFICATION
    - each holds DO_NOT_DELETE.txt containing a date

  Sites without a saved password are skipped unless -CredsFile is given, which supplies the
  password from a "username,password" file instead. Exit code 0 if every site passed.

.EXAMPLE
  .\test-winscp-sites.ps1
  .\test-winscp-sites.ps1 -Quiet
  .\test-winscp-sites.ps1 -Folder "FileGateway (no passwords)" -CredsFile $HOME\.filegw\users.csv
  # if scripts are blocked: powershell -ExecutionPolicy Bypass -File .\test-winscp-sites.ps1
#>
[CmdletBinding()]
param(
  [string]$Folder = 'FileGateway',
  [string]$CredsFile,
  [string]$WinSCPPath,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

$Folders = @('NOTIFICATION', 'SUBMISSION')
$Marker = 'DO_NOT_DELETE.txt'
$DatePattern = '^[A-Z][a-z]{2} [A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}:\d{2} [A-Za-z0-9+-]+ \d{4}$'

$dirs = @($WinSCPPath,
  (Join-Path $env:LOCALAPPDATA 'Programs\WinSCP'),
  (Join-Path ${env:ProgramFiles(x86)} 'WinSCP'),
  (Join-Path $env:ProgramFiles 'WinSCP')) |
  Where-Object { $_ -and (Test-Path (Join-Path $_ 'WinSCP.com')) }
if (-not $dirs) { throw 'WinSCP.com not found. Install WinSCP, or pass -WinSCPPath <folder that holds WinSCP.com>.' }
$winscp = Join-Path @($dirs)[0] 'WinSCP.com'

$passwords = @{}
if ($CredsFile) {
  Get-Content $CredsFile | ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('username,') -and $_.Contains(',') } |
    ForEach-Object { $i = $_.IndexOf(','); $passwords[$_.Substring(0, $i)] = $_.Substring($i + 1) }
}

# Saved sites in the folder, from WinSCP's registry storage. Read with the .NET registry API:
# site keys contain "/", which PowerShell's registry provider would treat as a path separator.
$sites = @()
$root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Martin Prikryl\WinSCP 2\Sessions')
if ($root) {
  try {
    $sites = @($root.GetSubKeyNames() |
      Where-Object { [Uri]::UnescapeDataString($_) -like "$Folder/*" } |
      ForEach-Object {
        $k = $root.OpenSubKey($_)
        try {
          [pscustomobject]@{
            Site        = [Uri]::UnescapeDataString($_)
            User        = $k.GetValue('UserName')
            HasPassword = [bool]$k.GetValue('Password')
          }
        } finally { $k.Close() }
      } | Sort-Object Site)
  } finally { $root.Close() }
}
if ($sites.Count -eq 0) { throw "No WinSCP sites in folder '$Folder'. Import them with .\import-winscp-sites.ps1" }

# WinSCP script arguments: quote, and double any embedded quotes
function Q([string]$s) { '"' + $s.Replace('"', '""') + '"' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("filegw-sites-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
$failed = New-Object System.Collections.Generic.List[string]
$skipped = 0
try {
  foreach ($s in $sites) {
    $open = "open $(Q $s.Site) -timeout=20"
    if (-not $s.HasPassword) {
      if (-not $passwords.ContainsKey($s.User)) { Write-Host "SKIP  $($s.Site) (no saved password; pass -CredsFile)" -ForegroundColor Yellow; $skipped++; continue }
      $open += " -password=$(Q $passwords[$s.User])"
    }
    $out = Join-Path $tmp $s.User
    New-Item -ItemType Directory $out | Out-Null
    # Script file rather than /command, so a password never shows in the process list
    $script = Join-Path $tmp "$($s.User).txt"
    $lines = @('option batch abort', 'option confirm off', $open, 'pwd', 'ls /')
    foreach ($d in $Folders) { $lines += "get $(Q "/$d/$Marker") $(Q (Join-Path $out "$d.txt"))" }
    $lines += 'exit'
    Set-Content -Path $script -Value $lines -Encoding ASCII

    $text = & $winscp /script=$script 2>&1 | Out-String
    $rc = $LASTEXITCODE
    Remove-Item $script -Force

    $problems = New-Object System.Collections.Generic.List[string]
    $details = New-Object System.Collections.Generic.List[string]
    $lines = @($text -split "`r?`n")
    if ($rc -ne 0) {
      $err = ($lines | Where-Object { $_ -match 'Access denied|Authentication failed|Connection failed|Network error|Error|failed|not exist|No such' } | Select-Object -First 3) -join ' / '
      if ($text -match "Host key wasn't verified") {
        # WinSCP reports a refused unknown host key as "Authentication failed" too; name the real cause
        $err = "server's host key isn't cached in WinSCP - run .\import-winscp-sites.ps1 to cache the pinned key"
      }
      $problems.Add("WinSCP exit $rc$(if ($err) { ": $err" })")
    } else {
      # pwd prints the remote directory on its own line, right after the session opens
      if (-not ($lines -contains '/')) { $problems.Add('did not open at /') }
      # ls lines end with the name; keep the folder entries listed under /
      $names = @($lines | Where-Object { $_ -cmatch '^[dD][-rwxsStT]{9}\s' } | ForEach-Object { ($_ -split '\s+')[-1] } |
        Where-Object { $_ -ne '.' -and $_ -ne '..' } | Sort-Object -Unique)
      $files = @($lines | Where-Object { $_ -cmatch '^-[-rwxsStT]{9}\s' })
      $details.Add("/: $($names -join ', ')")
      if (($names -join ',') -ne ($Folders -join ',') -or $files.Count -gt 0) {
        $problems.Add("/ holds [$((@($names) + @($files | ForEach-Object { ($_ -split '\s+')[-1] })) -join ', ')], expected only [$($Folders -join ', ')]")
      }
      foreach ($d in $Folders) {
        $f = Join-Path $out "$d.txt"
        if (-not (Test-Path $f)) { $problems.Add("/$d/$Marker missing"); continue }
        $c = (Get-Content -Raw $f).Trim()
        $details.Add("/$d/$Marker`: $c")
        if ($c -notmatch $DatePattern) { $problems.Add("/$d/$Marker doesn't contain a date: '$c'") }
      }
    }

    if ($problems.Count -eq 0) {
      Write-Host "PASS  $($s.Site)" -ForegroundColor Green
      if (-not $Quiet) { $details | ForEach-Object { Write-Host "      $_" } }
    } else {
      $failed.Add($s.Site)
      Write-Host "FAIL  $($s.Site)" -ForegroundColor Red
      $problems | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
      if (-not $Quiet) { $details | ForEach-Object { Write-Host "      $_" } }
    }
  }
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$tested = $sites.Count - $skipped
Write-Host ''
Write-Host "$($tested - $failed.Count) passed, $($failed.Count) failed, $skipped skipped (of $($sites.Count) sites in '$Folder')"
if ($failed.Count -gt 0) { Write-Host "Failed: $($failed -join ' ')"; exit 1 }
exit 0
