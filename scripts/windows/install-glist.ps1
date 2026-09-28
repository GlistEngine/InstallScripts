Add-Type -AssemblyName System.IO.Compression.FileSystem

# ---- options ----
# Set in the environment, which also works for `irm ... | iex`, or given as
# arguments when the script is run with -File (Glist Studio sets the variables):
#   --github-user NAME   GLIST_GITHUB_USERNAME=NAME  clone NAME's forks (default: GlistEngine)
#   --unattended         GLIST_UNATTENDED=1          never wait for Enter
#   --no-eclipse         GLIST_NO_ECLIPSE=1          no desktop shortcut, and Eclipse is not started
$Username = if ($env:GLIST_GITHUB_USERNAME) { $env:GLIST_GITHUB_USERNAME } else { "GlistEngine" }
$Unattended = [bool]$env:GLIST_UNATTENDED
$NoEclipse = [bool]$env:GLIST_NO_ECLIPSE
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--github-user" { $Username = $args[$i + 1]; $i++ }
        "--unattended" { $Unattended = $true }
        "--no-eclipse" { $NoEclipse = $true }
    }
}
# Unattended, git fails on a repository it cannot read instead of asking for a login.
if ($Unattended) { $env:GIT_TERMINAL_PROMPT = "0" }

# ---- progress ----
# Steps print as "==> [n/total] name", and the run ends with "==> Done: ..." or
# "==> Failed: ...", the same in all three installers, so a front end can follow.
$StepTotal = 6
$StepIndex = 0
function Step([string]$Name) {
    $script:StepIndex++
    Write-Host ""
    Write-Host "==> [$($script:StepIndex)/$StepTotal] $Name"
}
function Fail([string]$Message) {
    Write-Host "==> Failed: $Message"
    if (-not $Unattended) { Read-Host "Press Enter to exit" }
}

$GlistDir = "C:\dev\glist"
$GistAppsDir = "C:\dev\glist\myglistapps"
$GlistZbinDir = "C:\dev\glist\zbin"
$GlistZbinExtractedDir = "$GlistZbinDir\glistzbin-win64"
$EclipseLink = "$GlistZbinExtractedDir\GlistEngine-Win64.lnk"

$GlistEngineUrl = "https://github.com/$Username/GlistEngine"
$GlistAppUrl = "https://github.com/$Username/GlistApp"
$ZbinMetadataUrl = "https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/metadata/zbin-win64.json"

$GitPortableUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/MinGit-2.43.0-64-bit.zip"

# Define the path where Git Portable will be downloaded and extracted
$TempDirectory = "$env:TEMP\GlistInstaller"
$GitPortablePath = "$TempDirectory\GitPortable"

Step "Git"
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
        Fail "Could not extract Git: $_"
        return
    }

    # Add Git to the system PATH
    $env:Path += ";$GitPortablePath\cmd"
}

# Check if Git is now installed
if (Get-Command "git.exe" -ErrorAction SilentlyContinue) {
    Write-Host "Git is installed and available."
} else {
    Fail "Could not install Git"
    return
}

Step "Folders"
New-Item -ItemType Directory -Path $GlistDir -Force -ErrorAction Inquire | Out-Null
New-Item -ItemType Directory -Path $GistAppsDir -Force -ErrorAction Inquire | Out-Null
New-Item -ItemType Directory -Path $GlistZbinDir -Force -ErrorAction Inquire | Out-Null

Step "Glist tools (zbin)"
if (Test-Path $GlistZbinExtractedDir) {
    Write-Host "Zbin already exists at $GlistZbinExtractedDir, skipping download"
} else {
    # raw.githubusercontent serves .json as text/plain, so Invoke-RestMethod hands
    # back a string instead of an object. Parse it ourselves.
    try {
        $ZbinMetadata = (Invoke-WebRequest -Uri $ZbinMetadataUrl -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json
    } catch {
        Fail "Could not fetch the zbin metadata: $_"
        return
    }
    $GlistZbinZip = $ZbinMetadata.pattern
    $GlistZbinUrl = "https://github.com/$($ZbinMetadata.repo)/releases/download/$($ZbinMetadata.version)/$GlistZbinZip"
    Write-Host "Latest zbin release: $($ZbinMetadata.version)"
    Write-Host "Latest zbin release url: $GlistZbinUrl"

    # Since zbin url is redirecting, we cannot use bits transfer
    $ZbinArchive = "$TempDirectory\$GlistZbinZip"
    $webClient = New-Object System.Net.WebClient
    Write-Host "Downloading zbin file..."
    try {
        $webClient.DownloadFile($GlistZbinUrl, $ZbinArchive)
    } catch {
        Fail "Could not download the zbin: $_"
        return
    }
    Write-Host "Download successful."

    try {
        # Extract the archive
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZbinArchive, $GlistZbinDir)
        Write-Host "Extraction successful."
    } catch {
        Fail "Could not extract the zbin: $_"
        return
    }
}

Step "GlistEngine"
Set-Location -Path $GlistDir
if (Test-Path "$GlistDir\GlistEngine") {
    Write-Host "GlistEngine already exists, skipping"
} else {
    git clone $GlistEngineUrl
    if ($LASTEXITCODE -ne 0) { Fail "Could not clone GlistEngine from $Username"; return }
}

Step "GlistApp"
Set-Location -Path $GistAppsDir
if (Test-Path "$GistAppsDir\GlistApp") {
    Write-Host "GlistApp already exists, skipping"
} else {
    git clone $GlistAppUrl
    if ($LASTEXITCODE -ne 0) { Fail "Could not clone GlistApp from $Username"; return }
}

# Cleanup git portable
Remove-Item -Path $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue

Step "Eclipse"
if ($NoEclipse) {
    Write-Host "Skipped (--no-eclipse)"
} elseif (Test-Path $EclipseLink) {
    $Desktop = [Environment]::GetFolderPath("Desktop")
    Copy-Item -Path $EclipseLink -Destination "$Desktop\Start GlistEngine.lnk" -Force

    # Start Eclipse
    Start-Process -FilePath $EclipseLink
} else {
    Write-Host "Shortcut not found at $EclipseLink, skipping shortcut creation."
}

Write-Host ""
Write-Host "==> Done: Glist Engine is installed in $GlistDir"
