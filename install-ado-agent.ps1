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
$ZipName      = "vsts-agent-win-x64-$AgentVersion.zip"
$DownloadUrl  = "https://download.agent.dev.azure.com/agent/$AgentVersion/$ZipName"
$AgentRoot    = "C:\azagent"
$ZipPath      = Join-Path $env:TEMP $ZipName
# ===============

Write-Host "=== Azure DevOps Agent Installation Started ==="

# TLS 1.2
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

# Best-effort remove previous config (if any)
try {
  $existingConfig = Get-ChildItem -Path $AgentRoot -Recurse -Filter "config.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existingConfig) {
    Push-Location $existingConfig.Directory.FullName
    try { .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null } catch {}
    Pop-Location
  }
} catch {}

# Clean contents
Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Downloading agent: $DownloadUrl"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 180

Write-Host "Extracting to: $AgentRoot"
Expand-Archive -Path $ZipPath -DestinationPath $AgentRoot -Force

# Find config.cmd + svc.cmd anywhere under AgentRoot (robust)
$configCmd = Get-ChildItem -Path $AgentRoot -Recurse -Filter "config.cmd" -ErrorAction SilentlyContinue | Select-Object -First 1
$svcCmd    = Get-ChildItem -Path $AgentRoot -Recurse -Filter "svc.cmd"    -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $configCmd) { throw "config.cmd not found after extract under $AgentRoot" }
if (-not $svcCmd)    { throw "svc.cmd not found after extract under $AgentRoot (wrong ZIP package?)" }

Write-Host "Found config.cmd: $($configCmd.FullName)"
Write-Host "Found svc.cmd   : $($svcCmd.FullName)"

$workDir = $configCmd.Directory.FullName
Push-Location $workDir
try {
  Write-Host "Configuring agent..."
  & $configCmd.FullName --unattended `
    --url $AzureDevOpsOrgUrl `
    --auth pat `
    --token $PersonalAccessToken `
    --pool $AgentPool `
    --agent $AgentName `
    --runAsService `
    --work "_work" `
    --replace `
    --acceptTeeEula

  if ($LASTEXITCODE -ne 0) { throw "config.cmd failed with exit code $LASTEXITCODE" }

  Write-Host "Installing service..."
  & $svcCmd.FullName install
  if ($LASTEXITCODE -ne 0) { throw "svc.cmd install failed with exit code $LASTEXITCODE" }

  Write-Host "Starting service..."
  & $svcCmd.FullName start
  if ($LASTEXITCODE -ne 0) { throw "svc.cmd start failed with exit code $LASTEXITCODE" }

  Write-Host "=== Azure DevOps Agent Installed Successfully ==="
}
finally {
  Pop-Location
}
