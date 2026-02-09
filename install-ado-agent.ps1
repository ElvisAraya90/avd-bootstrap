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

function Ensure-Tls12 {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run as Administrator." }
}

function Get-LatestAgentZipUrl {
  Ensure-Tls12
  $headers = @{ "User-Agent" = "ado-agent-installer" }
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest" -Headers $headers
  $asset = $rel.assets | Where-Object { $_.name -match "win-x64.*\.zip$" } | Select-Object -First 1
  if (-not $asset) { throw "Could not find Windows x64 agent zip in latest release." }
  return $asset.browser_download_url
}

Write-Host "=== Azure DevOps Agent Installation Started ==="
Assert-Admin
Ensure-Tls12

$agentRoot = "C:\azagent"
$zipPath   = Join-Path $env:TEMP "ado-agent.zip"

New-Item -ItemType Directory -Force -Path $agentRoot | Out-Null
Set-Location $agentRoot

# If previously configured, try remove (best effort)
if (Test-Path (Join-Path $agentRoot "config.cmd")) {
  try {
    Write-Host "Removing existing agent config (best effort)..."
    .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null
  } catch {}
}

# Clean folder contents (keep folder)
Get-ChildItem -Path $agentRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Getting latest agent download URL from GitHub releases..."
$zipUrl = Get-LatestAgentZipUrl
Write-Host "Downloading agent: $zipUrl"
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60

Write-Host "Extracting agent..."
Expand-Archive -Path $zipPath -DestinationPath $agentRoot -Force

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
