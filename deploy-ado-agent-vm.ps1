<# 
.SYNOPSIS
  Installs and configures a self-hosted Azure DevOps agent on Windows as a service.

.REQUIREMENTS
  - Run as Administrator
  - Outbound HTTPS to dev.azure.com
  - A PAT token with: Agent Pools (Read & manage) scope
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$AzureDevOpsOrgUrl,     # e.g. https://dev.azure.com/ElvitoLab

  [Parameter(Mandatory=$true)]
  [string]$PersonalAccessToken,   # PAT with Agent Pools (Read & manage)

  [string]$AgentPool = "Default",
  [string]$AgentName = $env:COMPUTERNAME,
  [string]$AgentRoot = "C:\ado-agent",
  [string]$WorkFolder = "_work",

  # Use a dedicated service account? Leave empty to run as Local Service.
  [string]$ServiceLogonAccount = "",
  [string]$ServiceLogonPassword = ""
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw "Run this script in an elevated PowerShell (Run as Administrator)." }
}

function Ensure-Tls12 {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  } catch { }
}

function Get-LatestAgentDownloadUrl {
  # Microsoft agent releases: https://github.com/microsoft/azure-pipelines-agent/releases
  # Use GitHub API for latest Windows x64 zip.
  Ensure-Tls12
  $api = "https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest"
  $headers = @{ "User-Agent" = "ado-agent-installer" }
  $rel = Invoke-RestMethod -Uri $api -Headers $headers
  $asset = $rel.assets | Where-Object { $_.name -match "win-x64.*\.zip$" } | Select-Object -First 1
  if (-not $asset) { throw "Could not find win-x64 agent zip in latest release." }
  return $asset.browser_download_url
}

function Stop-And-UninstallIfExists {
  param([string]$Path)

  $configCmd = Join-Path $Path "config.cmd"
  if (-not (Test-Path $configCmd)) { return }

  # If already configured, remove it to make script re-runnable cleanly
  try {
    Push-Location $Path

    # Stop service if exists
    $svc = Get-Service -Name "vstsagent*" -ErrorAction SilentlyContinue
    if ($svc) {
      foreach ($s in $svc) {
        try { Stop-Service $s.Name -Force -ErrorAction SilentlyContinue } catch {}
      }
    }

    # Unconfigure if agent is configured
    # config.cmd remove requires the same auth type (PAT)
    & .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null
  } catch {
    # If remove fails (e.g., not configured), ignore
  } finally {
    Pop-Location
  }
}

# ---------------- MAIN ----------------
Assert-Admin
Ensure-Tls12

Write-Host "== Azure DevOps Agent Installer =="
Write-Host "Org:   $AzureDevOpsOrgUrl"
Write-Host "Pool:  $AgentPool"
Write-Host "Name:  $AgentName"
Write-Host "Path:  $AgentRoot"
Write-Host ""

# Create folder
New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

# If folder already contains an agent, cleanly remove it (idempotent)
Stop-And-UninstallIfExists -Path $AgentRoot

# Download latest agent zip
$zipUrl = Get-LatestAgentDownloadUrl
$zipPath = Join-Path $env:TEMP "ado-agent-win-x64.zip"

Write-Host "== Downloading agent: $zipUrl =="
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

Write-Host "== Extracting agent to $AgentRoot =="
# Clean folder but keep it
Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -Path $zipPath -DestinationPath $AgentRoot -Force

# Configure agent
Push-Location $AgentRoot
try {
  Write-Host "== Configuring agent (unattended) =="
  $commonArgs = @(
    "configure",
    "--unattended",
    "--url", $AzureDevOpsOrgUrl,
    "--auth", "pat",
    "--token", $PersonalAccessToken,
    "--pool", $AgentPool,
    "--agent", $AgentName,
    "--work", $WorkFolder,
    "--replace",
    "--acceptTeeEula"
  )

  if ([string]::IsNullOrWhiteSpace($ServiceLogonAccount)) {
    # Run as Local Service
    $args = $commonArgs + @("--runAsService")
    & .\config.cmd @args
  } else {
    if ([string]::IsNullOrWhiteSpace($ServiceLogonPassword)) {
      throw "ServiceLogonPassword is required when ServiceLogonAccount is specified."
    }

    # Run as specific user (domain/local)
    $args = $commonArgs + @(
      "--runAsService",
      "--windowsLogonAccount", $ServiceLogonAccount,
      "--windowsLogonPassword", $ServiceLogonPassword
    )
    & .\config.cmd @args
  }

  Write-Host "== Starting service =="
  # Service name usually like: vstsagent.<org>.<pool>.<agent>
  $svc = Get-Service -Name "vstsagent*" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
  if ($svc) {
    Start-Service $svc.Name
    Set-Service $svc.Name -StartupType Automatic
    Write-Host "✅ Service started: $($svc.Name)"
  } else {
    Write-Host "⚠️ Could not auto-detect service name. Check Services (services.msc) for vstsagent*."
  }

  Write-Host ""
  Write-Host "✅ Azure DevOps agent installation completed."
  Write-Host "Next: Azure DevOps → Project settings → Agent pools → $AgentPool → verify agent is Online."
}
finally {
  Pop-Location
}
