# install-fslogix.ps1
$ErrorActionPreference = 'Stop'

$uri  = 'https://aka.ms/fslogix_download'
$zip  = 'C:\Temp\fslogix.zip'
$path = 'C:\Temp\fslogix'

New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $uri -OutFile $zip -UseBasicParsing

if (Test-Path $path) { Remove-Item $path -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $path -Force

$exe = Join-Path $path 'x64\Release\FSLogixAppsSetup.exe'
Start-Process -FilePath $exe -ArgumentList '/install /quiet /norestart' -Wait

