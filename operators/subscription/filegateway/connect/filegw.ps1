<#
Connect to the file gateway from Windows 10/11 (uses the built-in OpenSSH client).

  .\filegw.ps1 ssh                 interactive shell (run `df -h` to see the S3 mapping)
  .\filegw.ps1 sftp                interactive SFTP session
  .\filegw.ps1 put FILE...         upload files into submission/
  .\filegw.ps1 s3 [aws s3 ARGS]    use the whole bucket with the AWS CLI (needs `oc login`)
                                   default: ls s3://filegateway/ --recursive

Env overrides: FILEGW_KEY (private key, default ~\.ssh\contabo_okd),
               FILEGW_HOST, FILEGW_PORT, FILEGW_USER
If scripts are blocked: powershell -ExecutionPolicy Bypass -File .\filegw.ps1 ssh
#>
param([Parameter(Position = 0)][string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Rest)
$ErrorActionPreference = 'Stop'

$Key    = if ($env:FILEGW_KEY)  { $env:FILEGW_KEY }  else { Join-Path $HOME '.ssh\contabo_okd' }
$Server = if ($env:FILEGW_HOST) { $env:FILEGW_HOST } else { '62.84.179.61' }
$Port   = if ($env:FILEGW_PORT) { $env:FILEGW_PORT } else { '30022' }
$User   = if ($env:FILEGW_USER) { $env:FILEGW_USER } else { 'ray' }
$Bucket = 'filegateway'

# Pinned host keys from the repo, so a new PC verifies the server instead of trusting on first use
$KnownHosts = Join-Path $PSScriptRoot 'known_hosts'
$SshOpts = @('-i', $Key, '-o', 'IdentitiesOnly=yes', '-o', "UserKnownHostsFile=$KnownHosts",
             '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=30')

function Assert-Key {
    if (-not (Test-Path $Key)) { throw "Private key not found: $Key (copy it from your Mac, or set FILEGW_KEY)" }
}

function Invoke-S3 {
    foreach ($tool in 'oc', 'aws') {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool CLI not found on PATH" }
    }
    oc whoami *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Not logged in: oc login --server=https://api.okd.funky-bash.com:6443' }

    $decode = { param($b64) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
    $env:AWS_ACCESS_KEY_ID     = & $decode (oc get secret $Bucket -n filegateway -o jsonpath='{.data.AWS_ACCESS_KEY_ID}')
    $env:AWS_SECRET_ACCESS_KEY = & $decode (oc get secret $Bucket -n filegateway -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}')
    $env:AWS_DEFAULT_REGION    = 'us-east-1'

    $lport = 18080
    $pf = Start-Process oc -ArgumentList 'port-forward', '-n', 'rook-ceph', 'svc/rook-ceph-rgw-objectstore', "${lport}:8080" `
        -NoNewWindow -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName())
    try {
        for ($i = 0; $i -lt 30; $i++) {
            if ((Test-NetConnection localhost -Port $lport -WarningAction SilentlyContinue).TcpTestSucceeded) { break }
            Start-Sleep -Milliseconds 500
        }
        $s3args = if ($Rest) { $Rest } else { @('ls', "s3://$Bucket/", '--recursive') }
        aws --endpoint-url "http://localhost:$lport" s3 @s3args
    } finally {
        Stop-Process -Id $pf.Id -ErrorAction SilentlyContinue
    }
}

switch ($Command) {
    'ssh'  { Assert-Key; ssh @SshOpts -p $Port "$User@$Server" @Rest }
    'sftp' { Assert-Key; sftp @SshOpts -P $Port "$User@$Server" }
    'put'  {
        Assert-Key
        if (-not $Rest) { throw 'usage: .\filegw.ps1 put FILE...' }
        $batch = @('cd submission') + ($Rest | ForEach-Object { "put `"$_`"" })
        $batch | sftp @SshOpts -P $Port -b - "$User@$Server"
    }
    's3'   { Invoke-S3 }
    default { Write-Host 'usage: .\filegw.ps1 ssh | sftp | put FILE... | s3 [aws s3 ARGS]'; exit 1 }
}
