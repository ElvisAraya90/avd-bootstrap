param(
  [Parameter(Mandatory=$true)]
  [string]$RegistrationToken,

  [Parameter(Mandatory=$true)]
  [string]$FslogixScriptName,

  [string]$TempPath = "C:\Temp\AVD"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Force -Path $TempPath | Out-Null

function Assert-RealMsi {
  param([string]$Path, [string]$Name)
  if (!(Test-Path $Path)) { throw "$Name not found at $Path" }

  $len = (Get-Item $Path).Length
  if ($len -lt 1000000) { throw "$Name is too small ($len bytes). Likely HTML/redirect content, not MSI." }

  $head = Get-Content -Path $Path -TotalCount 1 -ErrorAction SilentlyContinue
  if ($head -match "<!doctype html|<html") { throw "$Name appears to be HTML, not MSI." }
}

Write-Host "== Running FSLogix installer script =="
$fslogixLocal = Join-Path $TempPath $FslogixScriptName
Copy-Item -Path (Join-Path $PSScriptRoot $FslogixScriptName) -Destination $fslogixLocal -Force
powershell -NoProfile -ExecutionPolicy Bypass -File $fslogixLocal

Write-Host "== Downloading AVD bootloader + agent =="
$boot  = Join-Path $TempPath "AVD-Bootloader.msi"
$agent = Join-Path $TempPath "AVD-Agent.msi"

# Prefer aka.ms but validate hard
Invoke-WebRequest -Uri "https://aka.ms/avd/bootloader" -OutFile $boot -MaximumRedirection 10 -UseBasicParsing
Invoke-WebRequest -Uri "https://aka.ms/avd/agent"      -OutFile $agent -MaximumRedirection 10 -UseBasicParsing

Assert-RealMsi -Path $boot  -Name "AVD Bootloader MSI"
Assert-RealMsi -Path $agent -Name "AVD Agent MSI"

Write-Host "== Installing AVD bootloader =="
Start-Process msiexec.exe -ArgumentList "/i", "`"$boot`"", "/qn", "/norestart" -Wait -NoNewWindow

Write-Host "== Installing AVD agent + registration token =="
Start-Process msiexec.exe -ArgumentList "/i", "`"$agent`"", "/qn", "/norestart", "REGISTRATIONTOKEN=$RegistrationToken" -Wait -NoNewWindow

Write-Host "== Bootstrap complete =="
