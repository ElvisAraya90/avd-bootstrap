$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$base = 'C:\Temp\AVD'
$logDir = Join-Path $base 'Logs'
$zip  = Join-Path $base 'fslogix.zip'
$path = Join-Path $base 'fslogix'
$uri  = 'https://aka.ms/fslogix_download'

New-Item -ItemType Directory -Path $base -Force | Out-Null
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Start-Transcript -Path (Join-Path $logDir "install-fslogix-$(Get-Date -Format yyyyMMdd-HHmmss).log") | Out-Null

try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  Write-Host "Downloading FSLogix..."
  Invoke-WebRequest -Uri $uri -OutFile $zip -MaximumRedirection 10 -UseBasicParsing

  if (Test-Path $path) { Remove-Item $path -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $path -Force

  $exe = Join-Path $path 'x64\Release\FSLogixAppsSetup.exe'
  if (!(Test-Path $exe)) { throw "FSLogix installer not found at $exe" }

  Write-Host "Installing FSLogix..."
  $p = Start-Process -FilePath $exe -ArgumentList '/install /quiet /norestart' -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "FSLogix install failed with exit code $($p.ExitCode)" }

  Write-Host "FSLogix installed successfully."
}
finally {
  Stop-Transcript | Out-Null
}
