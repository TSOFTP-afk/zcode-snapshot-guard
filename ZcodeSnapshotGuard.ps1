# ============================================================================
#  ZcodeSnapshotGuard.ps1  -  ZCode snapshot killer sentinel (dual-layer)
#  ----------------------------------------------------------------------------
#  Layer 1 (ACL):     Deny write on %USERPROFILE%\.zcode\v2\checkpoints so
#                     snapshot artifacts can never be created. Owner can always
#                     re-grant, so NO admin required.
#  Layer 2 (Sentinel): background loop that deletes any snapshot artifact
#                     (*.tar.gz.enc, *.envelope.json, anything inside
#                     checkpoints\ or pending\) under the ZCode data root.
#  Log:               %USERPROFILE%\.zcode-guard.log
#  Compatibility:     Windows PowerShell 5.1+ (no pwsh7 needed), ASCII only.
#  License:           MIT
# ============================================================================
#Requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('install','status','sweep','uninstall','run')]
  [string]$Action = 'status',

  # ZCode data root. Default matches the Windows desktop client.
  [string]$Root = (Join-Path $env:USERPROFILE '.zcode')
)

$ErrorActionPreference = 'SilentlyContinue'
$GuardLog    = Join-Path $env:USERPROFILE '.zcode-guard.log'
$StartupCmd  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\zcode-snapshot-guard.cmd'
$Checkpoints = Join-Path $Root 'v2\checkpoints'
$ScriptFile  = $PSCommandPath

function Write-Info([string]$m)  { Write-Host ("[*] " + $m) }
function Write-Bad([string]$m)   { Write-Host ("[!] " + $m) -ForegroundColor Yellow }
function Write-Ok([string]$m)    { Write-Host ("[+] " + $m) -ForegroundColor Green }

function Test-AclDenyActive {
  if (-not (Test-Path -LiteralPath $Checkpoints)) { return $false }
  $probe = Join-Path $Checkpoints ('.guard-probe-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType Directory -Path $probe -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    return $false
  } catch { return $true }
}

function Remove-AnyWay([string]$p) {
  for ($i = 0; $i -lt 8; $i++) {
    try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; return 'deleted' } catch { }
    # fallback: cmd del works even where PS Remove-Item is blocked by attribute ACLs
    $null = cmd /c del /f /q "$p" 2>&1
    if (-not (Test-Path -LiteralPath $p)) { return 'deleted-cmd' }
    Start-Sleep -Milliseconds 400
  }
  return 'locked'
}

function Invoke-Sweep {
  if (-not (Test-Path -LiteralPath $Root)) { return 0 }
  $killed = 0
  $all = Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue
  foreach ($f in $all) {
    $inCp  = ($f.FullName -like '*\checkpoints\*') -or ($f.FullName -like '*\pending\*')
    $isArt = ($f.Name -like '*.tar.gz.enc') -or ($f.Name -like '*.envelope.json')
    if ($inCp -or $isArt) {
      $r = Remove-AnyWay $f.FullName
      if ($r -like 'deleted*') { $killed++ }
    }
  }
  return $killed
}

function Get-SentinelPid {
  $me = $PID
  $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    if ($p.ProcessId -ne $me -and $p.CommandLine -match 'ZcodeSnapshotGuard' -and $p.CommandLine -match 'run') { return [int]$p.ProcessId }
  }
  return $null
}

function Enable-AclDeny {
  if (-not (Test-Path -LiteralPath $Checkpoints)) {
    New-Item -ItemType Directory -Force -Path $Checkpoints | Out-Null
  }
  $null = icacls $Checkpoints /deny "$($env:USERNAME):(OI)(CI)(WD,AD)"
  if (Test-AclDenyActive) { Write-Ok ("ACL write-deny ACTIVE: " + $Checkpoints) }
  else { Write-Bad "ACL deny NOT active (unexpected)." }
}

function Disable-AclDeny {
  if (Test-Path -LiteralPath $Checkpoints) {
    $null = icacls $Checkpoints /remove:d "$($env:USERNAME)"
    Write-Info "ACL deny removed."
  }
}

function Install-Autostart {
  $engine = (Get-Process -Id $PID).Path
  if (-not $engine) { $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
  $nl = [Environment]::NewLine
  $line = '@echo off' + $nl +
          'start "zcode-guard" /min "' + $engine + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ScriptFile + '" -Action run -Root "' + $Root + '"' + $nl
  # ASCII only on purpose: .cmd files without BOM are read as ANSI on zh-CN systems
  [IO.File]::WriteAllText($StartupCmd, $line, (New-Object System.Text.ASCIIEncoding))
  Write-Ok ("Autostart installed: " + $StartupCmd)
}

function Start-Sentinel {
  $existing = Get-SentinelPidr
  if ($existing) { Write-Ok ("Sentinel already running (pid " + $existing + ")"); return }
  $engine = (Get-Process -Id $PID).Path
  if (-not $engine) { $engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
  Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',("'" + $ScriptFile + "'"),'-Action','run','-Root',("'" + $Root + "'")) -WindowStyle Hidden
  Start-Sleep -Seconds 2
  $now = Get-SentinelPidr
  if ($now) { Write-Ok ("Sentinel started (pid " + $now + ")") } else { Write-Bad "Sentinel failed to start (check log)." }
}

function Show-Status {
  Write-Info ("data root : " + $Root + (Test-Path -LiteralPath $Root ? ' [exists]' : ' [missing]'))
}

switch ($Action) {
  'status'    { Show-Status }
  'sweep'     {
    $n = Invoke-Sweep
    Write-Ok ("sweep done, deleted " + $n + " artifact(s)")
  }
  'install'   {
    Enable-AclDeny
    Install-Autostart
    Start-Sentinel
    Show-Status
  }
  'uninstall' {
    $spid = Get-SentinelPid
    if ($spid) { Stop-Process -Id $spid -Force; Write-Info ("sentinel stopped (pid " + $spid + ")") }
    if (Test-Path -LiteralPath $StartupCmd) { Remove-Item -LiteralPath $StartupCmd -Force; Write-Info "autostart removed." }
    Disable-AclDeny
    Write-Ok "uninstall complete. Log kept at: " + $GuardLog
  }
  'run'       {
    $created = $falser
    $mutex = New-Object System.Threading.Mutex($true, 'Local\zcode-snapshot-guard', [ref]$created)
    if (-not $created) { exit 0 }
    function Write-GuardLog([string]$m) {
      try { Add-Content -LiteralPath $GuardLog -Value ("[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] " + $m) -Encoding ASCII } catch {}
    }
    Write-GuardLog ("guard started (pid " + $PID + ")")
    while ($true) {
      $n = Invoke-Sweep
      if ($n -gt 0) { Write-GuardLog ("sweep removed " + $n + " file(s)") }
      Start-Sleep -Seconds 5
    }
  }
}
