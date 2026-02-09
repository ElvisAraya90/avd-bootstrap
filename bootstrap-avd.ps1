param(
  [Parameter(Mandatory=$true)]
  [string]$RegistrationToken,

  [Parameter(Mandatory=$true)]
  [string]$FslogixScriptName,

  [string]$TempPath = "C:\Temp\AVD"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Force -Path $TempPath | Out-Null

Write-Host "== Running FSLogix installer script =="
$fslogixLocal = Join-Path $TempPath $FslogixScriptName
Copy-Item -Path (Join-Path $PSScriptRoot $FslogixScriptName) -Destination $fslogixLocal -Force
powershell -NoProfile -ExecutionPolicy Bypass -File $fslogixLocal

Write-Host "== Downloading AVD bootloader + agent =="
$boot = Join-Path $TempPath "AVD-Bootloader.msi"
$agent = Join-Path $TempPath "AVD-Agent.msi"

Invoke-WebRequest -Uri "https://aka.ms/avd/bootloader" -OutFile $boot
Invoke-WebRequest -Uri "https://aka.ms/avd/agent" -OutFile $agent

Write-Host "== Installing AVD bootloader =="
Start-Process msiexec.exe -ArgumentList "/i", $boot, "/qn", "/norestart" -Wait

Write-Host "== Installing AVD agent + registration token =="
Start-Process msiexec.exe -ArgumentList "/i", $agent, "/qn", "/norestart", "REGISTRATIONTOKEN=$RegistrationToken" -Wait

Write-Host "== Bootstrap complete =="
