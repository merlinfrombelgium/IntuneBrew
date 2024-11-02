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
#>

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
# App registration details required for certificate-based authentication
$appid = '<YourAppIdHere>' # Enterprise App (Service Principal) App ID
$tenantid = '<YourTenantIdHere>' # Your tenant ID
$certThumbprint = '<YourCertificateThumbprintHere>' # Certificate thumbprint from your certificate store

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

# Auhentication END

# Import required modules
Import-Module Microsoft.Graph.Authentication

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

# Compares version strings accounting for build numbers
function Is-NewerVersion($githubVersion, $intuneVersion) {
    if ($intuneVersion -eq 'Not in Intune') {
        return $true
    }

    try {
        # Handle simple numeric versions (e.g., "15")
        if ($githubVersion -match '^\d+$' -and $intuneVersion -match '^\d+$') {
            return [int]$githubVersion -gt [int]$intuneVersion
        }

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
        Write-Host "Version comparison failed: GitHubVersion='$githubVersion', IntuneVersion='$intuneVersion'. Using string comparison." -ForegroundColor Yellow
        # Fallback to simple string comparison
        return $githubVersion -ne $intuneVersion
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


# Retrieves and compares app versions between Intune and GitHub
function Get-IntuneApps {
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

# Add Windows Forms assembly
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Add function to get supported app names from JSON files
function Get-SupportedAppNames {
    # Get the script's directory path
    $scriptPath = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = (Get-Location).Path
    }
    
    $appsPath = Join-Path $scriptPath "Apps"
    Write-Host "Loading UI. Please wait..." -ForegroundColor Gray
    
    if (Test-Path $appsPath) {
        # Get all JSON files and extract their base names (without extension)
        $jsonFiles = Get-ChildItem -Path $appsPath -Filter "*.json"
        return $jsonFiles | ForEach-Object { 
            # Create a mapping of display name to file name
            @{
                DisplayName = (Get-Content $_.FullName | ConvertFrom-Json).name
                FileName    = $_.BaseName
            }
        }
    }
    Write-Host "Warning: Apps directory not found at $appsPath" -ForegroundColor Yellow
    return @()
}

# Replace the table display and app selection logic with GUI
function Show-AppSelectionGui {
    param (
        $TableData
    )
    
    # Get supported apps with their display names
    $supportedApps = Get-SupportedAppNames
    if ($supportedApps.Count -eq 0) {
        Write-Host "No supported applications found in the Apps directory." -ForegroundColor Red
        return $null
    }

    # Create a hashtable for quick lookup of supported apps
    $supportedAppsLookup = @{}
    foreach ($app in $supportedApps) {
        $supportedAppsLookup[$app.DisplayName] = $app.FileName
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'IntuneBrew - App Selection'
    $form.Size = New-Object System.Drawing.Size(1200, 800)
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [System.Drawing.Color]::White

    # Create search box and buttons panel at top
    $topPanel = New-Object System.Windows.Forms.Panel
    $topPanel.Location = New-Object System.Drawing.Point(10, 10)
    $topPanel.Size = New-Object System.Drawing.Size(1160, 30)

    # Create search box (adjusted width to make room for buttons)
    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Location = New-Object System.Drawing.Point(0, 0)
    $searchBox.Size = New-Object System.Drawing.Size(300, 20)
    $searchBox.PlaceholderText = "Search applications..."

    # Add "Show All" button (moved from bottom)
    $btnShowAll = New-Object System.Windows.Forms.Button
    $btnShowAll.Location = New-Object System.Drawing.Point(320, 0)
    $btnShowAll.Size = New-Object System.Drawing.Size(120, 25)
    $btnShowAll.Text = "Show All"
    $btnShowAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnShowAll.Add_Click({
            foreach ($card in $flowPanel.Controls) {
                $card.Visible = $true
                # Uncheck boxes when showing all
                $checkbox = $card.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] }
                if ($checkbox) {
                    $checkbox.Checked = $false
                }
            }
            # Clear the search box
            $searchBox.Text = ""
        })

    # Add "Show Available Updates" button
    $btnSelectUpdates = New-Object System.Windows.Forms.Button
    $btnSelectUpdates.Location = New-Object System.Drawing.Point(450, 0)
    $btnSelectUpdates.Size = New-Object System.Drawing.Size(150, 25)
    $btnSelectUpdates.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

   

    # Add controls to top panel
    $topPanel.Controls.AddRange(@($searchBox, $btnShowAll, $btnSelectUpdates))

    # Update FlowPanel location to account for new top panel layout
    $flowPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowPanel.Location = New-Object System.Drawing.Point(10, 50)
    $flowPanel.Size = New-Object System.Drawing.Size(1160, 650)
    $flowPanel.AutoScroll = $true
    $flowPanel.BackColor = [System.Drawing.Color]::WhiteSmoke
    $flowPanel.Padding = New-Object System.Windows.Forms.Padding(10)

    # Function to create app card
    function Create-AppCard($app) {
        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size(350, 150)
        $card.BackColor = [System.Drawing.Color]::White
        $card.Margin = New-Object System.Windows.Forms.Padding(8)
        $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $card.Cursor = [System.Windows.Forms.Cursors]::Hand

        # Create a function to handle clicks that will be reused
        $clickHandler = {
            param($sender, $e)
            $parentCard = if ($sender -is [System.Windows.Forms.Panel]) { 
                $sender 
            }
            else { 
                $sender.Parent 
            }
            $checkbox = $parentCard.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] }
            if ($checkbox) {
                $checkbox.Checked = !$checkbox.Checked
            }
        }

        # Add click handler for the card
        $card.Add_Click($clickHandler)

        # Visual feedback on click
        $card.Add_MouseDown({
                $this.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)
            })

        $card.Add_MouseUp({
                $originalColor = $this.Tag -as [System.Drawing.Color]
                if ($originalColor) {
                    $this.BackColor = $originalColor
                }
            })

        $checkbox = New-Object System.Windows.Forms.CheckBox
        $checkbox.Location = New-Object System.Drawing.Point(10, 60)
        $checkbox.AutoSize = $true
        $checkbox.Tag = $app.'App Name'
        
        # Create and setup icon with larger size
        $icon = New-Object System.Windows.Forms.PictureBox
        # Increased icon size
        $icon.Size = New-Object System.Drawing.Size(96, 96)
        # Adjusted icon position
        $icon.Location = New-Object System.Drawing.Point(40, 26)
        $icon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $icon.Add_Click($clickHandler)

        # Try to load the app logo
        try {
            $logoFileName = $app.'App Name'.ToLower().Replace(" ", "_") + ".png"
            $logoUrl = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/Logos/$logoFileName"
            
            # Download the image to memory
            $webClient = New-Object System.Net.WebClient
            $imageBytes = $webClient.DownloadData($logoUrl)
            $memoryStream = New-Object System.IO.MemoryStream($imageBytes, 0, $imageBytes.Length)
            $icon.Image = [System.Drawing.Image]::FromStream($memoryStream)
        }
        catch {
            Write-Host "Could not load logo for $($app.'App Name'): $_" -ForegroundColor Yellow
        }

        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = $app.'App Name'
        $nameLabel.Location = New-Object System.Drawing.Point(150, 20)
        $nameLabel.Size = New-Object System.Drawing.Size(190, 20)
        $nameLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $nameLabel.Add_Click($clickHandler)

        $versionLabel = New-Object System.Windows.Forms.Label
        $versionLabel.Text = "Latest: $($app.'Latest Version')"
        $versionLabel.Location = New-Object System.Drawing.Point(150, 50)
        $versionLabel.Size = New-Object System.Drawing.Size(190, 20)
        $versionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $versionLabel.Add_Click($clickHandler)

        $intuneVersionLabel = New-Object System.Windows.Forms.Label
        $intuneVersionLabel.Text = "Intune: $($app.'Intune Version')"
        $intuneVersionLabel.Location = New-Object System.Drawing.Point(150, 80)
        $intuneVersionLabel.Size = New-Object System.Drawing.Size(190, 20)
        $intuneVersionLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $intuneVersionLabel.Add_Click($clickHandler)

        $statusLabel = New-Object System.Windows.Forms.Label
        $statusLabel.Location = New-Object System.Drawing.Point(150, 110)
        $statusLabel.Size = New-Object System.Drawing.Size(190, 20)
        $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
        $statusLabel.Add_Click($clickHandler)

        # Status label logic
        if ($app.'Intune Version' -eq 'Not in Intune') {
            $statusLabel.Text = "New App"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            #$card.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 245)
            $card.Tag = [System.Drawing.Color]::FromArgb(255, 245, 245)
        }
        elseif ((Is-NewerVersion $app.'Latest Version' $app.'Intune Version')) {
            $statusLabel.Text = "Update Available"
            $statusLabel.ForeColor = [System.Drawing.Color]::Orange
            $card.BackColor = [System.Drawing.Color]::FromArgb(255, 250, 240)
            $card.Tag = [System.Drawing.Color]::FromArgb(255, 250, 240)
        }
        else {
            $statusLabel.Text = "Up to date"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            $card.BackColor = [System.Drawing.Color]::FromArgb(240, 255, 240)
            $card.Tag = [System.Drawing.Color]::FromArgb(240, 255, 240)
        }

        # Add all controls to the card
        $card.Controls.AddRange(@($checkbox, $icon, $nameLabel, $versionLabel, $intuneVersionLabel, $statusLabel))

        return $card
    }

    # Add app cards to flow panel
    foreach ($app in ($TableData | Sort-Object 'App Name')) {
        if ($app.'App Name') {
            $card = Create-AppCard $app
            $flowPanel.Controls.Add($card)
        }
    }

    # Calculate initial update count
    $initialUpdateCount = ($flowPanel.Controls | ForEach-Object {
            $statusLabel = $_.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Location.Y -eq 110 }
            if ($statusLabel -and $statusLabel.Text -eq "Update Available") {
                1
            }
            else {
                0
            }
        } | Measure-Object -Sum).Sum

    # Set initial button text with count
    $btnSelectUpdates.Text = "$initialUpdateCount Updates Available"

    $btnSelectUpdates.Add_Click({
            $updateCount = 0
            $newAppCount = 0
            foreach ($card in $flowPanel.Controls) {
                $statusLabel = $card.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Location.Y -eq 110 }
                $checkbox = $card.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] }
                if ($statusLabel) {
                    # Count separately for updates and new apps
                    if ($statusLabel.Text -eq "Update Available") {
                        $updateCount++
                        $card.Visible = $true
                    }
                    elseif ($statusLabel.Text -eq "New App") {
                        $newAppCount++
                        $card.Visible = $false  # Hide new apps
                    }
                    else {
                        $card.Visible = $false  # Hide up-to-date apps
                    }
                
                    # Remove the checkbox selection
                    if ($checkbox) {
                        $checkbox.Checked = $false
                    }
                }
            }
            # Update button text with only update count
            $btnSelectUpdates.Text = "$updateCount Updates Available"
        })

    # Add search functionality
    $searchBox.Add_TextChanged({
            $searchText = $searchBox.Text.ToLower()
            foreach ($card in $flowPanel.Controls) {
                $appName = $card.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] -and $_.Font.Bold } | Select-Object -First 1
                if ($appName) {
                    $card.Visible = $appName.Text.ToLower().Contains($searchText)
                }
            }
        })

    # Update button panel (now only contains OK button)
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Location = New-Object System.Drawing.Point(10, 710)
    $buttonPanel.Size = New-Object System.Drawing.Size(1160, 40)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Location = New-Object System.Drawing.Point(1050, 0)
    $btnOK.Size = New-Object System.Drawing.Size(100, 30)
    $btnOK.Text = "Close"
    $btnOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOK.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    # Add OK button to button panel
    $buttonPanel.Controls.Add($btnOK)

    # Update form controls
    $form.Controls.Clear()
    $form.Controls.AddRange(@($topPanel, $flowPanel, $buttonPanel))
    $form.AcceptButton = $btnOK
    $form.CancelButton = $btnCancel

    # Show form and get result
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedApps = @()
        foreach ($card in $flowPanel.Controls) {
            $checkbox = $card.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckBox] }
            if ($checkbox -and $checkbox.Checked) {
                $appName = $checkbox.Tag
                if ($supportedAppsLookup.ContainsKey($appName)) {
                    $selectedApps += $supportedAppsLookup[$appName]
                }
            }
        }
        return $selectedApps
    }
    return $null
}

# Replace the existing app selection code with:
$selectedApps = Show-AppSelectionGui $tableData
if ($null -eq $selectedApps) {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    Disconnect-MgGraph > $null 2>&1
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    exit 0
}

# Reset githubJsonUrls for actual processing
$githubJsonUrls = @()
foreach ($app in $selectedApps) {
    # Construct the GitHub JSON URL
    $jsonUrl = "https://raw.githubusercontent.com/ugurkocde/IntuneBrew/main/Apps/$app.json"
    $githubJsonUrls += $jsonUrl
}

if ($githubJsonUrls.Count -eq 0) {
    Write-Host "No valid applications selected. Exiting..." -ForegroundColor Red
    exit
}

# Get current versions from Intune
$intuneAppVersions = Get-IntuneApps

# Filter apps that need to be uploaded
$appsToUpload = @()
foreach ($jsonUrl in $githubJsonUrls) {
    $appInfo = Get-GitHubAppInfo -jsonUrl $jsonUrl
    if ($appInfo -eq $null) { continue }
    
    $intuneVersion = ($intuneAppVersions | Where-Object { $_.Name -eq $appInfo.name }).IntuneVersion
    if ($intuneVersion -eq $null) { $intuneVersion = 'Not in Intune' }
    
    if ($intuneVersion -eq 'Not in Intune' -or (Is-NewerVersion $appInfo.version $intuneVersion)) {
        $appsToUpload += @{
            Name          = $appInfo.name
            GitHubVersion = $appInfo.version
            IntuneVersion = $intuneVersion
        }
    }
}

if ($appsToUpload.Count -eq 0) {
    Write-Host "`nAll apps are up-to-date. No uploads necessary." -ForegroundColor Green
    Disconnect-MgGraph > $null 2>&1
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    exit 0
}

# Create custom message based on app statuses
$newApps = @($appsToUpload | Where-Object { $_.IntuneVersion -eq 'Not in Intune' })
$updatableApps = @($appsToUpload | Where-Object { $_.IntuneVersion -ne 'Not in Intune' })

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

# Prompt user to continue
$continue = Read-Host -Prompt $message
if ($continue -ne "y") {
    Write-Host "Operation cancelled by user." -ForegroundColor Yellow
    Disconnect-MgGraph > $null 2>&1
    Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    exit 0
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
    Write-Host "✅ Upload completed successfully" -ForegroundColor Green

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
#Disconnect-MgGraph > $null 2>&1
Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green

