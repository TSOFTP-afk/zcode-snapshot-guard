#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Optional layer-3 network quarantine for ZCode (zcode-snapshot-guard project).

.DESCRIPTION
  Mode B (-TelemetryHosts): pin known telemetry endpoints (Aliyun SLS/RUM used
  by the ZCode client) to 0.0.0.0 in the hosts file. Mild, reversible;
  does NOT stop snapshot uploads (OSS endpoints are issued dynamically).

  Mode A (-FirewallBlock): outbound firewall block for ZCode.exe - quarantine
  mode. Kills ALL ZCode network traffic INCLUDING the model API. Use only while
  you are not using ZCode at all.

  Why not "block Aliyun IP ranges"? Because the model API itself (e.g.
  open.bigmodel.cn) is also hosted on Aliyun IPs, and Windows Firewall has no
  domain-based rules - you would cut your own model access.
.EXAMPLE
  .\Block-ZcodeNetwork.ps1 -TelemetryHosts
  .\Block-ZcodeNetwork.ps1 -FirewallBlock -ZcodeExe F:\Zcode\ZCode.exe
  .\Block-ZcodeNetwork.ps1 -Undo
#>
[CmdletBinding()]
param(
  [string]$ZcodeExe = '',
  [switch]$FirewallBlock,
  [switch]$TelemetryHosts,
  [switch]$Undo
)

$ErrorActionPreference = 'Stop'
$RuleName = 'zcode-snapshot-guard: block ZCode.exe outbound'
$HostsPath   = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$HostsBackup = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts.zsg-backup'
$HBegin = '# BEGIN zcode-snapshot-guard (telemetry pins)'
$HEnd   = '# END zcode-snapshot-guard'
$Pins = @(
  '0.0.0.0 sdk.rum.aliyuncs.com',
  '0.0.0.0 proj-xtrace-7e235817c9b9381c22d8b743908d469f-cn-beijing.cn-beijing.log.aliyuncs.com'
)

function Resolve-ZcodeExe {
  if ($ZcodeExe -and (Test-Path $ZcodeExe)) { return $ZcodeExe }
  $candidates = @(
    'F:\Zcode\ZCode.exe',
    (Join-Path $env:LOCALAPPDATA 'Programs\zcode\ZCode.exe'),
    (Join-Path $env:ProgramFiles 'Zcode\ZCode.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Zcode\ZCode.exe')
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  throw "ZCode.exe not found. Pass -ZcodeExe explicitly."
}

if ($Undo) {
  Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  Write-Host '[+] firewall rule removed (if any)'
  if (Test-Path $HostsBackup) {
    Copy-Item $HostsBackup $HostsPath -Force
    Remove-Item $HostsBackup -Force
    Write-Host '[+] hosts restored from backup'
  }
  return
}

if ($FirewallBlock) {
  $exe = Resolve-ZcodeExe
  New-NetFirewallRule -DisplayName $RuleName -Direction Outbound -Action Block -Program $exe -Profile Any | Out-Null
  Write-Host ("[+] outbound BLOCKED for: " + $exe)
  Write-Host '[!] quarantine mode: model API is also blocked. Use -Undo to restore.'
}

if ($TelemetryHosts) {
  if (-not (Test-Path $HostsBackup)) { Copy-Item $HostsPath $HostsBackup -Force }
  $raw = Get-Content $HostsPath -ErrorAction SilentlyContinue
  $kept = @()
  $inside = $false
  foreach ($line in $raw) {
    if ($line -eq $HBegin) { $inside = $true; continue }
    if ($line -eq $HEnd)   { $inside = $false; continue }
    if (-not $inside) { $kept += $line }
  }
  $new = $kept + @($HBegin) + $Pins + @($HEnd)
  Set-Content -Path $HostsPath -Value $new -Encoding ASCII
  Write-Host '[+] telemetry endpoints pinned in hosts (backup at hosts.zsg-backup)'
  Write-Host '[!] note: snapshot upload endpoints are dynamic; use layer 1/2 (ACL + sentinel) for those.'
}

if (-not ($FirewallBlock -or $TelemetryHosts)) {
  Write-Host 'Nothing to do. Pass -FirewallBlock and/or -TelemetryHosts (or -Undo).'
}
