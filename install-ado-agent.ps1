param(
  [Parameter(Mandatory=$true)]
  [string]$AzureDevOpsOrgUrl,

  [Parameter(Mandatory=$true)]
  [string]$PersonalAccessToken,

  [Parameter(Mandatory=$true)]
  [string]$AgentPool,

  [Parameter(Mandatory=$true)]
  [string]$AgentName
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$AgentVersion = "4.269.0"
$DownloadUrl  = "https://download.agent.dev.azure.com/agent/4.269.0/pipelines-agent-win-x64-4.269.0.zip"
$AgentRoot    = "C:\azagent"
$ZipPath      = Join-Path $env:TEMP "ado-agent.zip"

Write-Host "=== Azure DevOps Agent Installation Started ==="

# TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Ensure folder
New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

# Clean old install (best effort)
if (Test-Path (Join-Path $AgentRoot "config.cmd")) {
  try {
    Push-Location $AgentRoot
    .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null
  } catch {} finally { Pop-Location }
}

Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Downloading agent from: $DownloadUrl"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 120

Write-Host "Extracting agent to: $AgentRoot"
Expand-Archive -Path $ZipPath -DestinationPath $AgentRoot -Force

# Validate expected files
$configCmd = Join-Path $AgentRoot "config.cmd"
$svcCmd    = Join-Path $AgentRoot "svc.cmd"

if (-not (Test-Path $configCmd)) { throw "config.cmd not found after extract. AgentRoot=$AgentRoot" }
if (-not (Test-Path $svcCmd))    { throw "svc.cmd not found after extract. AgentRoot=$AgentRoot" }

Push-Location $AgentRoot
try {
  Write-Host "Configuring agent (pool=$AgentPool, name=$AgentName, org=$AzureDevOpsOrgUrl)..."
  & $configCmd --unattended `
    --url $AzureDevOpsOrgUrl `
    --auth pat `
    --token $PersonalAccessToken `
    --pool $AgentPool `
    --agent $AgentName `
    --runAsService `
    --work "_work" `
    --replace `
    --acceptTeeEula

  if ($LASTEXITCODE -ne 0) {
    throw "config.cmd failed with exit code $LASTEXITCODE. Most common: PAT not authorized / wrong scope."
  }

  Write-Host "Installing service..."
  & $svcCmd install
  if ($LASTEXITCODE -ne 0) { throw "svc.cmd install failed with exit code $LASTEXITCODE" }

  Write-Host "Starting service..."
  & $svcCmd start
  if ($LASTEXITCODE -ne 0) { throw "svc.cmd start failed with exit code $LASTEXITCODE" }

  Write-Host "=== Azure DevOps Agent Installed Successfully ==="
} finally {
  Pop-Location
}
