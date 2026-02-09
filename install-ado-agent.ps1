param(
  [Parameter(Mandatory=$true)][string]$AzureDevOpsOrgUrl,
  [Parameter(Mandatory=$true)][string]$PersonalAccessToken,
  [Parameter(Mandatory=$true)][string]$AgentPool,
  [Parameter(Mandatory=$true)][string]$AgentName
)

$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"

# CONFIG
$AgentVersion = "4.269.0"
$ZipName      = "vsts-agent-win-x64-$AgentVersion.zip"
$DownloadUrl  = "https://download.agent.dev.azure.com/agent/$AgentVersion/$ZipName"
$AgentRoot    = "C:\azagent"
$ZipPath      = Join-Path $env:TEMP $ZipName
$LogPath      = Join-Path $AgentRoot "install.log"

function Log($msg) {
  $line = "[{0}] {1}" -f (Get-Date).ToString("s"), $msg
  Write-Host $line
  try { Add-Content -Path $LogPath -Value $line } catch {}
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

Log "=== START ADO AGENT INSTALL ==="
Log "OrgUrl: $AzureDevOpsOrgUrl"
Log "Pool : $AgentPool"
Log "Name : $AgentName"
Log "DownloadUrl: $DownloadUrl"

New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

# Clean folder
Get-ChildItem -Path $AgentRoot -Force -ErrorAction SilentlyContinue |
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $AgentRoot | Out-Null

Log "Downloading zip to $ZipPath"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 180

Log "Extracting zip to $AgentRoot"
Expand-Archive -Path $ZipPath -DestinationPath $AgentRoot -Force

# Find config.cmd
$configCmd = Get-ChildItem -Path $AgentRoot -Recurse -Filter "config.cmd" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $configCmd) { throw "config.cmd not found after extract under $AgentRoot" }

Log "Found config.cmd: $($configCmd.FullName)"
$workDir = $configCmd.Directory.FullName

# Remove old config if any (best effort)
Push-Location $workDir
try {
  if (Test-Path ".\.agent") {
    Log "Existing agent config detected, removing (best effort)..."
    try { .\config.cmd remove --unattended --auth pat --token $PersonalAccessToken | Out-Null } catch {}
  }

  Log "Running config.cmd (install as service)..."
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

  Log "Config complete. Looking for vstsagent service..."
}
finally {
  Pop-Location
}

Start-Sleep -Seconds 5

# Find service
$svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "vstsagent*" } | Select-Object -First 1
if (-not $svc) {
  # Sometimes service appears with delay; try a bit
  Start-Sleep -Seconds 10
  $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "vstsagent*" } | Select-Object -First 1
}

if (-not $svc) {
  throw "Agent service not found (expected service name like 'vstsagent.*'). Check $LogPath and $AgentRoot for files."
}

Log "Found service: $($svc.Name) (Status=$($svc.Status))"

if ($svc.Status -ne "Running") {
  Log "Starting service..."
  Start-Service -Name $svc.Name
  Start-Sleep -Seconds 3
  $svc = Get-Service -Name $svc.Name
  Log "Service status after start: $($svc.Status)"
}

if ($svc.Status -ne "Running") {
  throw "Service did not reach Running state. Check $LogPath."
}

Log "=== SUCCESS: ADO AGENT INSTALLED & RUNNING ==="
