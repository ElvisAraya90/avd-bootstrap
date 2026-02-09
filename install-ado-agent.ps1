param(
  [Parameter(Mandatory=$true)][string]$AzureDevOpsOrgUrl,
  [Parameter(Mandatory=$true)][string]$PersonalAccessToken,
  [Parameter(Mandatory=$true)][string]$AgentPool,
  [Parameter(Mandatory=$true)][string]$AgentName
)

$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$AgentVersion = "4.269.0"
$ZipName      = "vsts-agent-win-x64-$AgentVersion.zip"
$DownloadUrl  = "https://download.agent.dev.azure.com/agent/$AgentVersion/$ZipName"
$AgentRoot    = "C:\azagent"
$ZipPath      = Join-Path $env:TEMP $ZipName

Write-Host "=== DEBUG ADO AGENT INSTALL ==="
Write-Host "DownloadUrl: $DownloadUrl"
Write-Host "AgentRoot  : $AgentRoot"
Write-Host "ZipPath    : $ZipPath"

New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null
Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Downloading..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 180

Write-Host "Extracting..."
Expand-Archive -Path $ZipPath -DestinationPath $AgentRoot -Force

Write-Host "Top files after extract (first 80):"
Get-ChildItem -Path $AgentRoot -Recurse -File |
  Select-Object -First 80 FullName |
  ForEach-Object { Write-Host $_.FullName }

Write-Host "Searching for config.cmd / svc.cmd:"
Get-ChildItem -Path $AgentRoot -Recurse -Filter "config.cmd" -File | Select-Object FullName | ForEach-Object { Write-Host ("FOUND config.cmd: " + $_.FullName) }
Get-ChildItem -Path $AgentRoot -Recurse -Filter "svc.cmd"    -File | Select-Object FullName | ForEach-Object { Write-Host ("FOUND svc.cmd   : " + $_.FullName) }

throw "STOP HERE (debug done). Next step: adjust install logic based on real file layout."
