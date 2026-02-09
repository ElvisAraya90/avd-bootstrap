param(
  [Parameter(Mandatory=$true)]
  [string]$AzureDevOpsOrgUrl,

  [Parameter(Mandatory=$true)]
  [string]$PersonalAccessToken,

  [Parameter(Mandatory=$true)]
  [string]$AgentPool,

  [Parameter(Mandatory=$true)]
  [string]$AgentName,

  # Pin a known-good agent version (GitHub release asset)
  [string]$AgentVersion = "4.269.0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Ensure-Tls12 {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run as Administrator." }
}

Assert-Admin
Ensure-Tls12

Write-Host "=== Azure DevOps Agent Installation Started ==="

$agentRoot = "C:\azagent"
$zipPath   = Join-Path $env:TEMP "ado-agent.zip"

# Newer releases use pipelines-agent-*, older use vsts-agent-*
$zipName1  = "pipelines-agent-win-x64-$AgentVersion.zip"
$zipName2  = "vsts-agent-win-x64-$AgentVersion.zip"

$dl1 = "https://github.com/microsoft/azure-pipelines-agent/releases/download/v$AgentVersion/$zipName1"
$dl2 = "https://github.com/microsoft/azure-pipelines-agent/releases/download/v$AgentVersion/$zipName2"

New-Item -ItemType Directory -Force -Path $agentRoot | Out-Null

# Best-effort remove if previously configured
if (Test-Path (Join-Path $agentRoot "config.cmd")) {
  try {
    Push-Location $agentRoot
    .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null
  } catch {} finally { Pop-Location }
}

# Clean folder contents
Get-ChildItem -Path $agentRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Downloading agent v$AgentVersion from GitHub releases..."
try {
  Invoke-WebRequest -Uri $dl1 -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
} catch {
  Write-Host "Primary download failed, trying fallback asset name..."
  Invoke-WebRequest -Uri $dl2 -OutFile $zipPath -UseBasicParsing -TimeoutSec 120
}

Write-Host "Extracting agent..."
Expand-Archive -Path $zipPath -DestinationPath $agentRoot -Force

Push-Location $agentRoot
try {
  Write-Host "Configuring agent..."
  .\config.cmd --unattended `
    --url $AzureDevOpsOrgUrl `
    --auth pat `
    --token $PersonalAccessToken `
    --pool $AgentPool `
    --agent $AgentName `
    --runAsService `
    --work "_work" `
    --replace `
    --acceptTeeEula

  Write-Host "Installing service..."
  .\svc.cmd install
  Write-Host "Starting service..."
  .\svc.cmd start

  Write-Host "=== Azure DevOps Agent Installed Successfully ==="
} finally {
  Pop-Location
}
