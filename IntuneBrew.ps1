<#
.SYNOPSIS
    IntuneBrew - Automated Intune app deployment using Homebrew cask information.

.DESCRIPTION
    This script automates the process of deploying macOS applications to Microsoft Intune
    using information from Homebrew casks. It fetches app details, creates Intune policies,
    and manages the deployment process.

.NOTES
    File Name      : IntuneBrew.ps1
    Author         : Ugur Koc
    Prerequisite   : PowerShell 7+, Microsoft Graph PowerShell SDK
    Version        : 0.3 Preview
    Date           : 2024-10-27

.LINK
    https://github.com/ugurkocde/IntuneBrew

.EXAMPLE
    .\IntuneBrew.ps1
    .\IntuneBrew.ps1 -GUI
#>

param (
    [switch]$GUI
)

Write-Host "
___       _                    ____                    
|_ _|_ __ | |_ _   _ _ __   ___| __ ) _ __ _____      __
 | || '_ \| __| | | | '_ \ / _ \  _ \| '__/ _ \ \ /\ / /
 | || | | | |_| |_| | | | |  __/ |_) | | |  __/\ V  V / 
|___|_| |_|\__|\__,_|_| |_|\___|____/|_|  \___| \_/\_/  
" -ForegroundColor Cyan

Write-Host "IntuneBrew - Automated macOS Application Deployment via Microsoft Intune" -ForegroundColor Green
Write-Host "Made by Ugur Koc with" -NoNewline; Write-Host " ❤️  and ☕" -NoNewline
Write-Host " | Version" -NoNewline; Write-Host " 0.3 Public Preview" -ForegroundColor Yellow -NoNewline
Write-Host " | Last updated: " -NoNewline; Write-Host "2024-10-27" -ForegroundColor Magenta
Write-Host ""
Write-Host "This is a preview version. If you have any feedback, please open an issue at https://github.com/ugurkocde/IntuneBrew/issues. Thank you!" -ForegroundColor Cyan
Write-Host "You can sponsor the development of this project at https://github.com/sponsors/ugurkocde" -ForegroundColor Red
Write-Host ""


# Authentication START
# Load configuration from JSON file
try {
    $config = Get-Content -Raw -Path "config.json" | ConvertFrom-Json
    $appid = $config.azure.appId
    $tenantid = $config.azure.tenantId
    $certThumbprint = $config.azure.certThumbprint
}
catch {
    Write-Host "Error loading config.json: $_" -ForegroundColor Red
    Write-Host "Please ensure config.json exists and contains valid credentials." -ForegroundColor Yellow
    exit 1
}

# Required Graph API permissions for app functionality
$requiredPermissions = @(
    "DeviceManagementApps.ReadWrite.All"
)

# Check if App ID, Tenant ID, or Certificate Thumbprint are set correctly
if (-not $appid -or $appid -eq '<YourAppIdHere>' -or
    -not $tenantid -or $tenantid -eq '<YourTenantIdHere>' -or
    -not $certThumbprint -or $certThumbprint -eq '<YourCertificateThumbprintHere>') {

    Write-Host "App ID, Tenant ID, or Certificate Thumbprint is missing or not set correctly." -ForegroundColor Red

    # Fallback to interactive sign-in if certificate-based authentication details are not provided
    $manualConnection = Read-Host "Would you like to attempt a manual interactive connection? (y/n)"
    if ($manualConnection -eq 'y') {
        Write-Host "Attempting manual interactive connection..." -ForegroundColor Yellow
        try {
            $permissionsList = $requiredPermissions -join ', '
            $connectionResult = Connect-MgGraph -Scopes $permissionsList -NoWelcome -ErrorAction Stop
            Write-Host "Successfully connected to Microsoft Graph using interactive sign-in." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to connect to Microsoft Graph via interactive sign-in. Error: $_" -ForegroundColor Red
            exit
        }
    }
    else {
        Write-Host "Script execution cancelled by user." -ForegroundColor Red
        exit
    }
}
else {
    # Connect to Microsoft Graph using certificate-based authentication
    try {
        $connectionResult = Connect-MgGraph -ClientId $appid -TenantId $tenantid -CertificateThumbprint $certThumbprint -NoWelcome -ErrorAction Stop
        Write-Host "Successfully connected to Microsoft Graph using certificate-based authentication." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to connect to Microsoft Graph. Error: $_" -ForegroundColor Red
        exit
    }
}

# Check and display the current permissions
$context = Get-MgContext
$currentPermissions = $context.Scopes

# Validate required permissions
$missingPermissions = $requiredPermissions | Where-Object { $_ -notin $currentPermissions }
if ($missingPermissions.Count -gt 0) {
    Write-Host "WARNING: The following permissions are missing:" -ForegroundColor Red
    $missingPermissions | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "Please ensure these permissions are granted to the app registration for full functionality." -ForegroundColor Yellow
    exit
}

Write-Host "All required permissions are present." -ForegroundColor Green

# Start Web Server for GUI if -GUI is specified
if ($GUI) {
    Write-Host "Checking requirements for GUI mode..." -ForegroundColor Yellow

    # Get the script directory path
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location -Path $scriptPath

    # Define virtual environment paths
    $venvPath = Join-Path $scriptPath ".venv"
    $venvPython = if ($IsWindows) { Join-Path $venvPath "Scripts\python.exe" } else { Join-Path $venvPath "bin/python" }
    $venvPip = if ($IsWindows) { Join-Path $venvPath "Scripts\pip.exe" } else { Join-Path $venvPath "bin/pip" }

    # Install UV if not already installed and verify Python version
    try {
        # Check if Python 3.11+ is installed first
        try {
            # Get Python version
            $pythonVersion = python -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Python is not installed. Please install Python 3.11 or higher." -ForegroundColor Red
                exit 1
            }
            if ([version]$pythonVersion -lt [version]"3.11") {
                Write-Host "❌ Python version $pythonVersion is not supported. Please install Python 3.11 or higher." -ForegroundColor Red
                exit 1
            }
            Write-Host "✅ Python $pythonVersion detected" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ Error checking Python version. Please install Python 3.11 or higher." -ForegroundColor Red
            Write-Host "Error details: $_" -ForegroundColor Yellow
            exit 1
        }

        # Now check UV
        $uvCheck = Get-Command uv -ErrorAction SilentlyContinue
        if (-not $uvCheck) {
            Write-Host "❌ UV not found. Installing UV..." -ForegroundColor Yellow
            winget install astral-sh.uv
            # Refresh PATH to include UV
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Host "✅ UV installed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "✅ UV detected" -ForegroundColor Green
        }

        # Create virtual environment if it doesn't exist
        if (-not (Test-Path $venvPath)) {
            Write-Host "Creating virtual environment..." -ForegroundColor Yellow
            python -m venv $venvPath
            Write-Host "✅ Virtual environment created" -ForegroundColor Green
        }

        # Verify virtual environment Python
        if (Test-Path $venvPython) {
            $venvPythonVersion = & $venvPython -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')" 2>&1
            if ($LASTEXITCODE -ne 0 -or [version]$venvPythonVersion -lt [version]"3.11") {
                Write-Host "❌ Virtual environment Python version $venvPythonVersion is not supported. Recreating virtual environment..." -ForegroundColor Red
                Remove-Item $venvPath -Recurse -Force
                python -m venv $venvPath
                $venvPythonVersion = & $venvPython -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')" 2>&1
            }
            Write-Host "✅ Virtual environment Python $venvPythonVersion detected" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Virtual environment Python not found at: $venvPython" -ForegroundColor Red
            exit 1
        }

        # Install required Python packages using UV in the virtual environment
        Write-Host "Installing required Python packages..." -ForegroundColor Yellow
        & $venvPython -m pip install uv
        & $venvPython -m uv pip install flask flask-cors
        Write-Host "✅ Python packages installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error setting up environment: $_" -ForegroundColor Red
        exit 1
    }

    Write-Host "Starting web server..." -ForegroundColor Yellow

    # Start the Flask app as a job with isolated environment
    $flaskJob = Start-Job -ScriptBlock {
        param($venvPython, $scriptPath)
        
        # Clear any existing Python-related environment variables
        Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
        Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
        Remove-Item Env:PATH -ErrorAction SilentlyContinue
        
        # Set minimal PATH with only what we need
        $env:PATH = "$(Split-Path $venvPython -Parent);$env:SystemRoot\system32;$env:SystemRoot"
        
        # Set virtual environment
        $env:VIRTUAL_ENV = Split-Path $venvPython -Parent | Split-Path -Parent
        
        Set-Location $scriptPath
        Write-Host "Starting Flask with Python: $venvPython"
        & $venvPython app.py
    } -ArgumentList $venvPython, $scriptPath

    Write-Host "Access the web app at http://127.0.0.1:3000" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow

    try {
        # Keep the script running and monitor the job
        while ($true) {
            $jobState = $flaskJob | Get-Job
            if ($jobState.State -eq 'Failed') {
                Write-Host "❌ Web server crashed. Error:" -ForegroundColor Red
                Receive-Job $flaskJob
                break
            }
            # Show job output in real-time
            Receive-Job $flaskJob
            Start-Sleep -Seconds 1
        }
    }
    finally {
        # Cleanup when the script exits
        if ($flaskJob) {
            Write-Host "`nStopping web server..." -ForegroundColor Yellow
            Stop-Job $flaskJob
            Remove-Job $flaskJob -Force
        }
        Write-Host "Web server stopped." -ForegroundColor Green
        exit 0
    }
}

# Authentication END

# Import required modules
Import-Module Microsoft.Graph.Authentication

# Fetch supported apps from GitHub repository
$supportedAppsUrl = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/refs/heads/main/supported_apps.json"
$githubJsonUrls = @()

try {
    # Fetch the supported apps JSON
    $supportedApps = Invoke-RestMethod -Uri $supportedAppsUrl -Method Get

    if (-not $GUI) {
        # Allow user to select which apps to process
        Write-Host "`nAvailable applications:" -ForegroundColor Cyan
        # Add Sort-Object to sort the app names alphabetically
        $supportedApps.PSObject.Properties | 
        Sort-Object Name | 
        ForEach-Object { 
            Write-Host "  - $($_.Name)" 
        }
        Write-Host "`nEnter app names separated by commas (or 'all' for all apps):"
        $selectedApps = Read-Host

        if ($selectedApps.Trim().ToLower() -eq 'all') {
            $githubJsonUrls = $supportedApps.PSObject.Properties.Value
        }
        else {
            $selectedAppsList = $selectedApps.Split(',') | ForEach-Object { $_.Trim().ToLower() }
            foreach ($app in $selectedAppsList) {
                if ($supportedApps.PSObject.Properties.Name -contains $app) {
                    $githubJsonUrls += $supportedApps.$app
                }
                else {
                    Write-Host "Warning: '$app' is not a supported application" -ForegroundColor Yellow
                }
            }
        }

        if ($githubJsonUrls.Count -eq 0) {
            Write-Host "No valid applications selected. Exiting..." -ForegroundColor Red
            exit
        }
    }
    else {
        # In GUI mode, just load all apps for the web interface to handle
        $githubJsonUrls = $supportedApps.PSObject.Properties.Value
    }
}
catch {
    Write-Host "Error fetching supported apps list: $_" -ForegroundColor Red
    exit
}

# Core Functions

# Fetches app information from GitHub JSON file
function Get-GitHubAppInfo {
    param(
        [string]$jsonUrl
    )

    if ([string]::IsNullOrEmpty($jsonUrl)) {
        Write-Host "Error: Empty or null JSON URL provided." -ForegroundColor Red
        return $null
    }

    try {
        $response = Invoke-RestMethod -Uri $jsonUrl -Method Get
        return @{
            name        = $response.name
            description = $response.description
            version     = $response.version
            url         = $response.url
            bundleId    = $response.bundleId
            homepage    = $response.homepage
            fileName    = $response.fileName
        }
    }
    catch {
        Write-Host "Error fetching app info from GitHub URL: $jsonUrl" -ForegroundColor Red
        Write-Host "Error details: $_" -ForegroundColor Red
        return $null
    }
}

# Downloads app installer file with progress indication
function Download-AppFile($url, $fileName) {
    $outputPath = Join-Path $PWD $fileName

    # Get file size before downloading
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head
        $fileSize = [math]::Round(($response.Headers.'Content-Length' / 1MB), 2)
        Write-Host "Downloading the app file ($fileSize MB) to $outputPath..."
    }
    catch {
        Write-Host "Downloading the app file to $outputPath..."
    }

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $outputPath
    return $outputPath
}

# Encrypts app file using AES encryption for Intune upload
function EncryptFile($sourceFile) {
    function GenerateKey() {
        $aesSp = [System.Security.Cryptography.AesCryptoServiceProvider]::new()
        $aesSp.GenerateKey()
        return $aesSp.Key
    }

    $targetFile = "$sourceFile.bin"
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = GenerateKey
    $hmac = [System.Security.Cryptography.HMACSHA256]::new()
    $hmac.Key = GenerateKey
    $hashLength = $hmac.HashSize / 8

    $sourceStream = [System.IO.File]::OpenRead($sourceFile)
    $sourceSha256 = $sha256.ComputeHash($sourceStream)
    $sourceStream.Seek(0, "Begin") | Out-Null
    $targetStream = [System.IO.File]::Open($targetFile, "Create")

    $targetStream.Write((New-Object byte[] $hashLength), 0, $hashLength)
    $targetStream.Write($aes.IV, 0, $aes.IV.Length)
    $transform = $aes.CreateEncryptor()
    $cryptoStream = [System.Security.Cryptography.CryptoStream]::new($targetStream, $transform, "Write")
    $sourceStream.CopyTo($cryptoStream)
    $cryptoStream.FlushFinalBlock()

    $targetStream.Seek($hashLength, "Begin") | Out-Null
    $mac = $hmac.ComputeHash($targetStream)
    $targetStream.Seek(0, "Begin") | Out-Null
    $targetStream.Write($mac, 0, $mac.Length)

    $targetStream.Close()
    $cryptoStream.Close()
    $sourceStream.Close()

    return [PSCustomObject][ordered]@{
        encryptionKey        = [System.Convert]::ToBase64String($aes.Key)
        fileDigest           = [System.Convert]::ToBase64String($sourceSha256)
        fileDigestAlgorithm  = "SHA256"
        initializationVector = [System.Convert]::ToBase64String($aes.IV)
        mac                  = [System.Convert]::ToBase64String($mac)
        macKey               = [System.Convert]::ToBase64String($hmac.Key)
        profileIdentifier    = "ProfileVersion1"
    }
}

# Handles chunked upload of large files to Azure Storage
function UploadFileToAzureStorage($sasUri, $filepath) {
    $blockSize = 4 * 1024 * 1024 # 4 MiB
    $fileSize = (Get-Item $filepath).Length
    $totalBlocks = [Math]::Ceiling($fileSize / $blockSize)

    $maxRetries = 3
    $retryCount = 0
    $uploadSuccess = $false

    while (-not $uploadSuccess -and $retryCount -lt $maxRetries) {
        try {
            $fileStream = [System.IO.File]::OpenRead($filepath)
            $blockId = 0
            $blockList = [System.Xml.Linq.XDocument]::Parse('<?xml version="1.0" encoding="utf-8"?><BlockList />')
            $blockBuffer = [byte[]]::new($blockSize)

            Write-Host "`nUploading file to Azure Storage (Attempt $($retryCount + 1) of $maxRetries):"
            Write-Host "Total size: $([Math]::Round($fileSize / 1MB, 2)) MB"
            Write-Host "Block size: $($blockSize / 1MB) MB"
            Write-Host ""

            while ($bytesRead = $fileStream.Read($blockBuffer, 0, $blockSize)) {
                $id = [System.Convert]::ToBase64String([System.BitConverter]::GetBytes([int]$blockId))
                $blockList.Root.Add([System.Xml.Linq.XElement]::new("Latest", $id))

                $uploadBlockSuccess = $false
                $blockRetries = 3
                while (-not $uploadBlockSuccess -and $blockRetries -gt 0) {
                    try {
                        Invoke-WebRequest -Method Put "$sasUri&comp=block&blockid=$id" `
                            -Headers @{"x-ms-blob-type" = "BlockBlob" } `
                            -Body ([byte[]]($blockBuffer[0..$($bytesRead - 1)])) `
                            -ErrorAction Stop | Out-Null
                        $uploadBlockSuccess = $true
                    }
                    catch {
                        $blockRetries--
                        if ($blockRetries -gt 0) {
                            Write-Host "Retrying block upload..." -ForegroundColor Yellow
                            Start-Sleep -Seconds 2
                        }
                        else {
                            throw
                        }
                    }
                }

                $percentComplete = [Math]::Round(($blockId + 1) / $totalBlocks * 100, 1)
                $uploadedMB = [Math]::Min(
                    [Math]::Round(($blockId + 1) * $blockSize / 1MB, 1),
                    [Math]::Round($fileSize / 1MB, 1)
                )
                $totalMB = [Math]::Round($fileSize / 1MB, 1)

                Write-Host "`rProgress: [$($percentComplete)%] $uploadedMB MB / $totalMB MB" -NoNewline

                $blockId++
            }

            Write-Host ""

            $fileStream.Close()

            Invoke-RestMethod -Method Put "$sasUri&comp=blocklist" -Body $blockList | Out-Null
            $uploadSuccess = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "`nUpload failed. Retrying in 5 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 5

                # Request a new SAS token
                Write-Host "Requesting new upload URL..." -ForegroundColor Yellow
                $newFileStatus = Invoke-MgGraphRequest -Method GET -Uri $fileStatusUri
                if ($newFileStatus.azureStorageUri) {
                    $sasUri = $newFileStatus.azureStorageUri
                    Write-Host "Received new upload URL" -ForegroundColor Green
                }
            }
            else {
                Write-Host "`nFailed to upload file after $maxRetries attempts." -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor Red
                throw
            }
        }
        finally {
            if ($fileStream) {
                $fileStream.Close()
            }
        }
    }
}

# Validates GitHub URL format for security
function Is-ValidUrl {
    param (
        [string]$url
    )

    if ($url -match "^https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/Apps/.*\.json$") {
        return $true
    }
    else {
        Write-Host "Invalid URL format: $url" -ForegroundColor Red
        return $false
    }
}

# Retrieves and compares app versions between Intune and GitHub
function Get-IntuneApps {
    param(
        [switch]$GuiMode
    )

    if ($GuiMode) {
        # For GUI mode, just get all macOS apps from Intune in one go with pagination
        $intuneApps = @()
        $baseUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp'))"
        $nextLink = $baseUri

        Write-Host "Fetching all macOS apps from Intune..." -ForegroundColor Yellow
        while ($nextLink) {
            try {
                Write-Host "Making Graph API request..." -ForegroundColor Gray
                $response = Invoke-MgGraphRequest -Uri $nextLink -Method Get -ErrorAction Stop
                Write-Host "Response received" -ForegroundColor Gray
                if ($response.value) {
                    Write-Host "Found $($response.value.Count) apps in this page" -ForegroundColor Gray
                    $intuneApps += $response.value
                }
                $nextLink = $response.'@odata.nextLink'
            }
            catch {
                Write-Host "Error fetching Intune apps: $_" -ForegroundColor Red
                Write-Host "Graph API Context: $(Get-MgContext | ConvertTo-Json)" -ForegroundColor Yellow
                return @()
            }
        }
        Write-Host "✅ Found $($intuneApps.Count) total apps in Intune" -ForegroundColor Green

        if ($intuneApps.Count -eq 0) {
            Write-Host "No apps found in Intune" -ForegroundColor Yellow
            return @()
        }

        # Return raw Intune data for Flask app to process
        $result = @($intuneApps | Where-Object { $_ -ne $null } | Select-Object displayName, primaryBundleVersion, '@odata.type' | ForEach-Object {
            @{
                Name = $_.displayName
                IntuneVersion = if ($_.primaryBundleVersion) { $_.primaryBundleVersion } else { "Not in Intune" }
                Type = $_.'@odata.type'
            }
        })

        Write-Host "Returning $($result.Count) processed apps" -ForegroundColor Green
        return $result
    }
    else {
        # Original behavior for CLI mode
        $intuneApps = @()

        foreach ($jsonUrl in $githubJsonUrls) {
            # Check if the URL is valid
            if (-not (Is-ValidUrl $jsonUrl)) {
                continue
            }

            # Fetch GitHub app info
            $appInfo = Get-GitHubAppInfo $jsonUrl
            if ($appInfo -eq $null) {
                Write-Host "Failed to fetch app info for $jsonUrl. Skipping." -ForegroundColor Yellow
                continue
            }

            $appName = $appInfo.name

            # Fetch Intune app info
            $intuneQueryUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp')) and displayName eq '$appName'"

            try {
                $response = Invoke-MgGraphRequest -Uri $intuneQueryUri -Method Get
                if ($response.value.Count -gt 0) {
                    $intuneApp = $response.value[0]
                    $intuneApps += [PSCustomObject]@{
                        Name          = $intuneApp.displayName
                        IntuneVersion = $intuneApp.primaryBundleVersion
                        GitHubVersion = $appInfo.version
                    }
                }
                else {
                    $intuneApps += [PSCustomObject]@{
                        Name          = $appName
                        IntuneVersion = 'Not in Intune'
                        GitHubVersion = $appInfo.version
                    }
                }
            }
            catch {
                Write-Host "Error fetching Intune app info for '$appName': $_"
            }
        }

        return $intuneApps
    }
}

# Compares version strings accounting for build numbers
function Is-NewerVersion($githubVersion, $intuneVersion) {
    if ($intuneVersion -eq 'Not in Intune') {
        return $true
    }

    try {
        # Remove hyphens and everything after them for comparison
        $ghVersion = $githubVersion -replace '-.*$'
        $itVersion = $intuneVersion -replace '-.*$'

        # Handle versions with commas (e.g., "3.5.1,16101")
        $ghVersionParts = $ghVersion -split ','
        $itVersionParts = $itVersion -split ','

        # Compare main version numbers first
        $ghMainVersion = [Version]($ghVersionParts[0])
        $itMainVersion = [Version]($itVersionParts[0])

        if ($ghMainVersion -ne $itMainVersion) {
            return ($ghMainVersion -gt $itMainVersion)
        }

        # If main versions are equal and there are build numbers
        if ($ghVersionParts.Length -gt 1 -and $itVersionParts.Length -gt 1) {
            $ghBuild = [int]$ghVersionParts[1]
            $itBuild = [int]$itVersionParts[1]
            return $ghBuild -gt $itBuild
        }

        # If versions are exactly equal
        return $githubVersion -ne $intuneVersion
    }
    catch {
        Write-Host "Version comparison failed: GitHubVersion='$githubVersion', IntuneVersion='$intuneVersion'. Assuming versions are equal." -ForegroundColor Yellow
        return $false
    }
}

# Downloads and adds app logo to Intune app entry
function Add-IntuneAppLogo {
    param (
        [string]$appId,
        [string]$appName
    )

    Write-Host "`n🖼️  Adding app logo..." -ForegroundColor Yellow

    try {
        # Construct the logo URL - only replace spaces with underscores
        $logoFileName = $appName.ToLower().Replace(" ", "_") + ".png"
        $logoUrl = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/Logos/$logoFileName"

        # For debugging
        Write-Host "Downloading logo from: $logoUrl" -ForegroundColor Gray

        # Download the logo
        $tempLogoPath = Join-Path $PWD "temp_logo.png"
        Invoke-WebRequest -Uri $logoUrl -OutFile $tempLogoPath

        # Convert the logo to base64
        $logoContent = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($tempLogoPath))

        # Prepare the request body
        $logoBody = @{
            "@odata.type" = "#microsoft.graph.mimeContent"
            "type"        = "image/png"
            "value"       = $logoContent
        }

        # Update the app with the logo
        $logoUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId"
        $updateBody = @{
            "@odata.type" = "#microsoft.graph.$appType"
            "largeIcon"   = $logoBody
        }

        Invoke-MgGraphRequest -Method PATCH -Uri $logoUri -Body ($updateBody | ConvertTo-Json -Depth 10)
        Write-Host "✅ Logo added successfully" -ForegroundColor Green

        # Cleanup
        if (Test-Path $tempLogoPath) {
            Remove-Item $tempLogoPath -Force
        }
    }
    catch {
        Write-Host "⚠️ Warning: Could not add app logo. Error: $_" -ForegroundColor Yellow
    }
}

# Filter apps that need to be uploaded
$appsToUpload = $intuneAppVersions | Where-Object { 
    $_.IntuneVersion -eq 'Not in Intune' -or (Is-NewerVersion $_.GitHubVersion $_.IntuneVersion)
}

if ($appsToUpload.Count -eq 0) {
    Write-Host "`nAll apps are up-to-date. No uploads necessary." -ForegroundColor Green
    Disconnect-MgGraph > $null 2>&1
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    exit 0
}

# Create custom message based on app statuses
$newApps = @($appsToUpload | Where-Object { $_.IntuneVersion -eq 'Not in Intune' })
$updatableApps = @($appsToUpload | Where-Object { $_.IntuneVersion -ne 'Not in Intune' -and (Is-NewerVersion $_.GitHubVersion $_.IntuneVersion) })

# Construct the message
if (($newApps.Length + $updatableApps.Length) -eq 0) {
    $message = "`nNo new or updatable apps found. Exiting..."
    Write-Host $message -ForegroundColor Yellow
    Disconnect-MgGraph > $null 2>&1
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    exit 0
}
elseif (($newApps.Length + $updatableApps.Length) -eq 1) {
    # Check if it's a new app or an update
    if ($newApps.Length -eq 1) {
        $message = "`nDo you want to upload this new app ($($newApps[0].Name)) to Intune? (y/n)"
    }
    elseif ($updatableApps.Length -eq 1) {
        $message = "`nDo you want to update this app ($($updatableApps[0].Name)) in Intune? (y/n)"
    }
    else {
        $message = "`nDo you want to process this app? (y/n)"
    }
}
else {
    $statusParts = @()
    if ($newApps.Length -gt 0) {
        $statusParts += "$($newApps.Length) new app$(if($newApps.Length -gt 1){'s'}) to upload"
    }
    if ($updatableApps.Length -gt 0) {
        $statusParts += "$($updatableApps.Length) app$(if($updatableApps.Length -gt 1){'s'}) to update"
    }
    $message = "`nFound $($statusParts -join ' and '). Do you want to continue? (y/n)"
}

# Prompt user to continue only in non-GUI mode
if (-not $GUI) {
    $continue = Read-Host -Prompt $message
    if ($continue -ne "y") {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        Disconnect-MgGraph > $null 2>&1
        Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
        exit 0
    }
}

# Main script for uploading only newer apps
foreach ($jsonUrl in $githubJsonUrls) {
    $appInfo = Get-GitHubAppInfo -jsonUrl $jsonUrl

    if ($appInfo -eq $null) {
        Write-Host "`n❌ Failed to fetch app info for $jsonUrl. Skipping." -ForegroundColor Red
        continue
    }

    # Check if this app needs to be uploaded/updated
    $currentApp = $intuneAppVersions | Where-Object { $_.Name -eq $appInfo.name }
    if ($currentApp -and $currentApp.IntuneVersion -ne 'Not in Intune' -and 
        !(Is-NewerVersion $appInfo.version $currentApp.IntuneVersion)) {
        continue
    }

    Write-Host "`n📦 Processing: $($appInfo.name)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    Write-Host "⬇️  Downloading application..." -ForegroundColor Yellow
    $appFilePath = Download-AppFile $appInfo.url $appInfo.fileName
    Write-Host "✅ Download complete" -ForegroundColor Green

    Write-Host "`n📋 Application Details:" -ForegroundColor Cyan
    Write-Host "   • Display Name: $($appInfo.name)"
    Write-Host "   • Version: $($appInfo.version)"
    Write-Host "   • Bundle ID: $($appInfo.bundleId)"
    Write-Host "   • File: $(Split-Path $appFilePath -Leaf)"

    $appDisplayName = $appInfo.name
    $appDescription = $appInfo.description
    $appPublisher = $appInfo.name
    $appHomepage = $appInfo.homepage
    $appBundleId = $appInfo.bundleId
    $appBundleVersion = $appInfo.version

    Write-Host "`n🔄 Creating app in Intune..." -ForegroundColor Yellow

    # Determine app type based on file extension
    $appType = if ($appInfo.fileName -match '\.dmg$') {
        "macOSDmgApp"
    }
    elseif ($appInfo.fileName -match '\.pkg$') {
        "macOSPkgApp"
    }
    else {
        Write-Host "❌ Unsupported file type. Only .dmg and .pkg files are supported." -ForegroundColor Red
        continue
    }

    $app = @{
        "@odata.type"                   = "#microsoft.graph.$appType"
        displayName                     = $appDisplayName
        description                     = $appDescription
        publisher                       = $appPublisher
        fileName                        = (Split-Path $appFilePath -Leaf)
        informationUrl                  = $appHomepage
        packageIdentifier               = $appBundleId
        bundleId                        = $appBundleId
        versionNumber                   = $appBundleVersion
        minimumSupportedOperatingSystem = @{
            "@odata.type" = "#microsoft.graph.macOSMinimumOperatingSystem"
            v11_0         = $true
        }
    }

    if ($appType -eq "macOSDmgApp" -or $appType -eq "macOSPkgApp") {
        $app["primaryBundleId"] = $appBundleId
        $app["primaryBundleVersion"] = $appBundleVersion
        $app["includedApps"] = @(
            @{
                "@odata.type" = "#microsoft.graph.macOSIncludedApp"
                bundleId      = $appBundleId
                bundleVersion = $appBundleVersion
            }
        )
    }

    $createAppUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
    $newApp = Invoke-MgGraphRequest -Method POST -Uri $createAppUri -Body ($app | ConvertTo-Json -Depth 10)
    Write-Host "✅ App created successfully (ID: $($newApp.id))" -ForegroundColor Green

    Write-Host "`n🔒 Processing content version..." -ForegroundColor Yellow
    $contentVersionUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)/microsoft.graph.$appType/contentVersions"
    $contentVersion = Invoke-MgGraphRequest -Method POST -Uri $contentVersionUri -Body "{}"
    Write-Host "✅ Content version created (ID: $($contentVersion.id))" -ForegroundColor Green

    Write-Host "`n🔐 Encrypting application file..." -ForegroundColor Yellow
    $encryptedFilePath = "$appFilePath.bin"
    if (Test-Path $encryptedFilePath) {
        Remove-Item $encryptedFilePath -Force
    }
    $fileEncryptionInfo = EncryptFile $appFilePath
    Write-Host "✅ Encryption complete" -ForegroundColor Green

    Write-Host "`n⬆️  Uploading to Azure Storage..." -ForegroundColor Yellow
    $fileContent = @{
        "@odata.type" = "#microsoft.graph.mobileAppContentFile"
        name          = [System.IO.Path]::GetFileName($appFilePath)
        size          = (Get-Item $appFilePath).Length
        sizeEncrypted = (Get-Item "$appFilePath.bin").Length
        isDependency  = $false
    }

    $contentFileUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)/microsoft.graph.$appType/contentVersions/$($contentVersion.id)/files"  
    $contentFile = Invoke-MgGraphRequest -Method POST -Uri $contentFileUri -Body ($fileContent | ConvertTo-Json)

    do {
        Start-Sleep -Seconds 5
        $fileStatusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)/microsoft.graph.$appType/contentVersions/$($contentVersion.id)/files/$($contentFile.id)"
        $fileStatus = Invoke-MgGraphRequest -Method GET -Uri $fileStatusUri
    } while ($fileStatus.uploadState -ne "azureStorageUriRequestSuccess")

    UploadFileToAzureStorage $fileStatus.azureStorageUri "$appFilePath.bin"
    Write-Host"✅ Upload completed successfully" -ForegroundColor Green

    Write-Host "`n🔄 Committing file..." -ForegroundColor Yellow
    $commitData = @{
        fileEncryptionInfo = $fileEncryptionInfo
    }
    $commitUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)/microsoft.graph.$appType/contentVersions/$($contentVersion.id)/files/$($contentFile.id)/commit"
    Invoke-MgGraphRequest -Method POST -Uri $commitUri -Body ($commitData | ConvertTo-Json)

    $retryCount = 0
    $maxRetries = 10
    do {
        Start-Sleep -Seconds 10
        $fileStatusUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)/microsoft.graph.$appType/contentVersions/$($contentVersion.id)/files/$($contentFile.id)"
        $fileStatus = Invoke-MgGraphRequest -Method GET -Uri $fileStatusUri
        if ($fileStatus.uploadState -eq "commitFileFailed") {
            $commitResponse = Invoke-MgGraphRequest -Method POST -Uri $commitUri -Body ($commitData | ConvertTo-Json)
            $retryCount++
        }
    } while ($fileStatus.uploadState -ne "commitFileSuccess" -and $retryCount -lt $maxRetries)

    if ($fileStatus.uploadState -eq "commitFileSuccess") {
        Write-Host "✅ File committed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "Failed to commit file after $maxRetries attempts."
        exit 1
    }

    $updateAppUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($newApp.id)"
    $updateData = @{
        "@odata.type"           = "#microsoft.graph.$appType"
        committedContentVersion = $contentVersion.id
    }
    Invoke-MgGraphRequest -Method PATCH -Uri $updateAppUri -Body ($updateData | ConvertTo-Json)

    Add-IntuneAppLogo -appId $newApp.id -appName $appInfo.name

    Write-Host "`n🧹 Cleaning up temporary files..." -ForegroundColor Yellow
    if (Test-Path $appFilePath) {
        try {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            Remove-Item $appFilePath -Force -ErrorAction Stop
        }
        catch {
            Write-Host "Warning: Could not remove $appFilePath. Error: $_" -ForegroundColor Yellow
        }
    }
    if (Test-Path "$appFilePath.bin") {
        $maxAttempts = 3
        $attempt = 0
        $success = $false

        while (-not $success -and $attempt -lt $maxAttempts) {
            try {
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
                Start-Sleep -Seconds 2  # Give processes time to release handles
                Remove-Item "$appFilePath.bin" -Force -ErrorAction Stop
                $success = $true
            }
            catch {
                $attempt++
                if ($attempt -lt $maxAttempts) {
                    Write-Host "Retry $attempt of $maxAttempts to remove encrypted file..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                }
                else {
                    Write-Host "Warning: Could not remove $appFilePath.bin. Error: $_" -ForegroundColor Yellow
                }
            }
        }
    }
    Write-Host "✅ Cleanup complete" -ForegroundColor Green

    Write-Host "`n✨ Successfully processed $($appInfo.name)" -ForegroundColor Cyan
    Write-Host "🔗 Intune Portal URL: https://intune.microsoft.com/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/$($newApp.id)" -ForegroundColor Cyan
    Write-Host "" -ForegroundColor Cyan
}

Write-Host "`n🎉 All operations completed successfully!" -ForegroundColor Green
Disconnect-MgGraph > $null 2>&1
Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green


# Authentication END