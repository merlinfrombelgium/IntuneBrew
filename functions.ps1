# Core Functions for IntuneBrew

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
function Is-NewerVersion {
    param($githubVersion, $intuneVersion)
    
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