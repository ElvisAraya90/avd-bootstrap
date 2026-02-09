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

Write-Host "=== Azure DevOps Agent Installation Started ==="

# -----------------------------
# Variables
# -----------------------------
$agentRoot = "C:\azagent"
$agentVersion = "3.239.1"   # Stable version
$agentPackage = "vsts-agent-win-x64-$agentVersion.zip"
$downloadUrl = "https://vstsagentpackage.azureedge.net/agent/$agentVersion/$agentPackage"

# -----------------------------
# Create folder
# -----------------------------
if (!(Test-Path $agentRoot)) {
    Write-Host "Creating agent directory $agentRoot"
    New-Item -ItemType Directory -Path $agentRoot | Out-Null
}

Set-Location $agentRoot

# -----------------------------
# Download agent
# -----------------------------
Write-Host "Downloading Azure DevOps agent..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $agentPackage -UseBasicParsing

Write-Host "Extracting package..."
Expand-Archive -Path $agentPackage -DestinationPath $agentRoot -Force

# -----------------------------
# Configure agent
# -----------------------------
Write-Host "Configuring agent..."

$env:VSTS_AGENT_INPUT_URL = $AzureDevOpsOrgUrl
$env:VSTS_AGENT_INPUT_AUTH = "pat"
$env:VSTS_AGENT_INPUT_TOKEN = $PersonalAccessToken
$env:VSTS_AGENT_INPUT_POOL = $AgentPool
$env:VSTS_AGENT_INPUT_AGENT = $AgentName
$env:VSTS_AGENT_INPUT_ACCEPTTSSLAUTH = "false"
$env:VSTS_AGENT_INPUT_RUNASSERVICE = "true"
$env:VSTS_AGENT_INPUT_WORK = "_work"
$env:VSTS_AGENT_INPUT_REPLACE = "true"

.\config.cmd --unattended `
    --url $AzureDevOpsOrgUrl `
    --auth pat `
    --token $PersonalAccessToken `
    --pool $AgentPool `
    --agent $AgentName `
    --acceptTeeEula `
    --runAsService `
    --work "_work" `
    --replace

# -----------------------------
# Install & start service
# -----------------------------
Write-Host "Installing service..."
.\svc.sh install

Write-Host "Starting service..."
.\svc.sh start

Write-Host "=== Azure DevOps Agent Installed Successfully ==="
