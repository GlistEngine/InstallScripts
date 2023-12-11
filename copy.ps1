$Desktop = [Environment]::GetFolderPath("Desktop")

$InstallerFolder = "$Desktop\Installer"
New-Item -ItemType Directory -Path $InstallerFolder -Force | Out-Null

$InstallerFile = "$InstallerFolder\install-glist.ps1"

Copy-Item -Path "C:\sandbox\install-glist.ps1" -Destination $InstallerFolder -Force

Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File $InstallerFile" -Wait
