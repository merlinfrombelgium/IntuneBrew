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

    # Check if Python3 is installed
    try {
        $pythonVersion = python3 --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Python3 is not installed. Please install Python3 to use GUI mode." -ForegroundColor Red
            exit 1
        }
        Write-Host "✅ Python3 detected: $pythonVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Python3 is not installed. Please install Python3 to use GUI mode." -ForegroundColor Red
        exit 1
    }

    # Install UV if not already installed
    try {
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

        # Verify virtual environment and packages
        Write-Host "Verifying Python virtual environment..." -ForegroundColor Yellow
        $venvPath = Join-Path $PWD ".venv"
        if (-not (Test-Path $venvPath)) {
            Write-Host "Creating virtual environment..." -ForegroundColor Yellow
            uv venv
            Write-Host "✅ Virtual environment created" -ForegroundColor Green
        }

        # Install required Python packages using UV
        Write-Host "Verifying required Python packages..." -ForegroundColor Yellow
        $venvPython = Join-Path $venvPath "Scripts" "python.exe"
        $pipList = & $venvPython -m pip list
        $needsPackages = -not ($pipList -match "flask" -and $pipList -match "flask-cors")
        
        if ($needsPackages) {
            Write-Host "Installing required Python packages..." -ForegroundColor Yellow
            uv pip install flask flask-cors
            Write-Host "✅ Python packages installed successfully" -ForegroundColor Green
        } else {
            Write-Host "✅ Required packages already installed" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "❌ Error installing dependencies: $_" -ForegroundColor Red
        exit 1
    }

    Write-Host "Starting web server..." -ForegroundColor Yellow

    # Get the script directory path
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location -Path $scriptPath

    # Read Flask app configuration
    try {
        $config = Get-Content "config.json" -Raw | ConvertFrom-Json
        $flaskPort = $config.webserver.port
    } catch {
        $flaskPort = "3000"  # Default fallback
    }

    # Start the Flask app using the virtual environment's Python directly
    $venvPath = Join-Path $scriptPath ".venv"
    $venvPython = Join-Path $venvPath "Scripts" "python.exe"
    
    if (-not (Test-Path $venvPython)) {
        Write-Host "❌ Virtual environment Python not found at $venvPython" -ForegroundColor Red
        exit 1
    }

    # Start Flask app directly with pwsh
    $pwshPath = (Get-Command pwsh).Source
    $flaskProcess = Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile", "-Command", "& '$venvPython' 'app.py'" -WindowStyle Hidden -PassThru

    # Give the server a moment to start
    Start-Sleep -Seconds 2

    # Check if process is still running
    if ($flaskProcess.HasExited) {
        Write-Host "❌ Flask server failed to start" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ Web server started successfully" -ForegroundColor Green
    Write-Host "Access the web app at http://127.0.0.1:$flaskPort" -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow

    try {
        while ($true) {
            if ($flaskProcess.HasExited) {
                Write-Host "Flask server stopped unexpectedly" -ForegroundColor Red
                break
            }
            Start-Sleep -Seconds 1
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Host "`nStopping server..." -ForegroundColor Yellow
    }
    finally {
        if (-not $flaskProcess.HasExited) {
            Stop-Process -Id $flaskProcess.Id -Force
        }
        Disconnect-MgGraph > $null 2>&1
        Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    }
    exit 0
}

# Authentication END

# Import required modules
Import-Module Microsoft.Graph.Authentication

# Source the functions
. (Join-Path $PSScriptRoot "functions.ps1")

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

# Retrieve Intune app versions
Write-Host "Fetching current Intune app versions..."
$intuneAppVersions = Get-IntuneApps
Write-Host ""

# Prepare table data
$tableData = @()
foreach ($app in $intuneAppVersions) {
    if ($app.IntuneVersion -eq 'Not in Intune') {
        $status = "Not in Intune"
        $statusColor = "Red"
    }
    elseif (Is-NewerVersion $app.GitHubVersion $app.IntuneVersion) {
        $status = "Update Available"
        $statusColor = "Yellow"
    }
    else {
        $status = "Up-to-date"
        $statusColor = "Green"
    }

    $tableData += [PSCustomObject]@{
        "App Name"       = $app.Name
        "Latest Version" = $app.GitHubVersion
        "Intune Version" = $app.IntuneVersion
        "Status"         = $status
        "StatusColor"    = $statusColor
    }
}

# Function to write colored table
function Write-ColoredTable {
    param (
        $TableData
    )

    $lineSeparator = "+----------------------------+----------------------+----------------------+-----------------+"

    Write-Host $lineSeparator
    Write-Host ("| {0,-26} | {1,-20} | {2,-20} | {3,-15} |" -f "App Name", "Latest Version", "Intune Version", "Status") -ForegroundColor Cyan
    Write-Host $lineSeparator

    foreach ($row in $TableData) {
        $color = $row.StatusColor
        Write-Host ("| {0,-26} | {1,-20} | {2,-20} | {3,-15} |" -f $row.'App Name', $row.'Latest Version', $row.'Intune Version', $row.Status) -ForegroundColor $color
        Write-Host $lineSeparator
    }
}

# Display the colored table with lines
Write-ColoredTable $tableData

# In GUI mode, stop here after displaying the status
if ($GUI) {
    Write-Host "`nStatus table displayed. GUI will handle further interactions." -ForegroundColor Green
    exit 0
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