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

# ==== CONFIG ====
$AgentVersion = "4.269.0"
$DownloadUrl  = "https://download.agent.dev.azure.com/agent/4.269.0/pipelines-agent-win-x64-4.269.0.zip"
$AgentRoot    = "C:\azagent"
$ZipPath      = Join-Path $env:TEMP "ado-agent.zip"
# ===============

Write-Host "=== Azure DevOps Agent Installation Started ==="

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Create directory
New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

# Clean existing install (if any)
if (Test-Path (Join-Path $AgentRoot "config.cmd")) {
    Push-Location $AgentRoot
    try {
        .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null
    } catch {}
    Pop-Location
}

Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue | 
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Downloading agent..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

Write-Host "Extracting agent..."
Expand-Archive -Path $ZipPath -DestinationPath $AgentRoot -Force

Push-Location $AgentRoot

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

Pop-Location

Write-Host "=== Azure DevOps Agent Installed Successfully ==="
