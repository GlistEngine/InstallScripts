Add-Type -AssemblyName System.IO.Compression.FileSystem

$GlistDir = "C:\dev\glist"
$GlistEngineDir = "C:\dev\glist\glistengine"
$GistAppsDir = "C:\dev\glist\myglistapps"
$GlistZbinDir = "C:\dev\glist\zbin"
$EclipseLink = "C:\dev\glist\zbin\glistzbin-win64\GlistEngine-Win64.lnk"

$GitHubUrl = "https://github.com/GlistEngine"
$GlistEngineUrl = "$GitHubUrl/GlistEngine"
$GlistAppUrl = "$GitHubUrl/glistapp"
$GlistZbinUrl = (Invoke-RestMethod -Uri "https://raw.githubusercontent.com/irrld/glist-urls/main/zbin-win64" -ErrorAction Inquire)
Write-Host "Latest zbin release url: $GlistZbinUrl"

$GitPortableUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/MinGit-2.43.0-64-bit.zip"

# Define the path where Git Portable will be downloaded and extracted
$TempDirectory = "$env:TEMP\GlistInstaller"
$GitPortablePath = "$TempDirectory\GitPortable"

New-Item -ItemType Directory -Path $TempDirectory -Force -ErrorAction Inquire | Out-Null

# Check if Git is already installed
if ((Get-Command "git.exe" -ErrorAction SilentlyContinue) -eq $null) {
    Write-Host "Git not installed, installing to $GitPortablePath"
    # Create a temporary directory for Git Portable

    Remove-Item -Path $GitPortablePath -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $GitPortablePath -Force -ErrorAction Inquire | Out-Null

    # Download Git Portable
    Start-BitsTransfer -Source $GitPortableUrl -Destination "$GitPortablePath\mingit.zip" -ErrorAction Inquire

    try {
        # Extract the archive
        [System.IO.Compression.ZipFile]::ExtractToDirectory("$GitPortablePath\mingit.zip", $GitPortablePath)
        Write-Host "Extraction successful."
    } catch {
        Write-Host "Error extracting archive: $_"
        Read-Host "Press Enter to exit"
        return
    }
    
    # Add Git to the system PATH
    $env:Path += ";$GitPortablePath\cmd"
}

# Check if Git is now installed
if (Get-Command "git.exe" -ErrorAction SilentlyContinue) {
    Write-Host "Git is installed and available."
} else {
    Write-Host "Failed to install Git."
    Read-Host "Press Enter to exit"
    return
}

# Create folders
New-Item -ItemType Directory -Path $GlistDir -Force -ErrorAction Inquire | Out-Null
New-Item -ItemType Directory -Path $GistAppsDir -Force -ErrorAction Inquire | Out-Null
New-Item -ItemType Directory -Path $GlistZbinDir -Force -ErrorAction Inquire | Out-Null

# Download and extract zbin
# Since zbin url is redirecting, we cannot use bits transfer
$webClient = New-Object System.Net.WebClient
Write-Host "Downloading zbin file..."
$webClient.DownloadFile($GlistZbinUrl, "$TempDirectory\glistzbin-win64.zip")
Write-Host "Download successful."

try {
    # Extract the archive
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$TempDirectory\glistzbin-win64.zip", $GlistZbinDir)
    Write-Host "Extraction successful."
} catch {
    Write-Host "Error extracting archive: $_"
    Read-Host "Press Enter to exit"
    return
}

# Clone repos
Set-Location -Path $GlistDir
git clone $GlistEngineURL
Set-Location -Path $GistAppsDir
git clone $GlistAppURL

# Cleanup git portable
Remove-Item -Path $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue

# Copy link
$Desktop = [Environment]::GetFolderPath("Desktop")
Copy-Item -Path $EclipseLink -Destination "$Desktop/Start GlistEngine.lnk" -Force

# Start Eclipse
Start-Process -FilePath $EclipseLink

#Read-Host "Press enter to exit"