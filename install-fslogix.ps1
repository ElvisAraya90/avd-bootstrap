$uri = "https://aka.ms/fslogix_download"
$zip = "C:\Temp\fslogix.zip"
$path = "C:\Temp\fslogix"

New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
Invoke-WebRequest -Uri $uri -OutFile $zip
Expand-Archive $zip $path -Force

Start-Process "$path\x64\Release\FSLogixAppsSetup.exe" `
  -ArgumentList "/install /quiet /norestart" `
  -Wait
