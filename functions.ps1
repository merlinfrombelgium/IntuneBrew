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
    # Disable verbose output for module operations
    $VerbosePreference = 'SilentlyContinue'
    
    try {
        # Get all macOS apps from Intune with pagination
        $filter = "(isof('microsoft.graph.macOSDmgApp') or isof('microsoft.graph.macOSPkgApp'))"
        $intuneApps = @()
        $nextLink = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$filter=$filter"

        do {
            $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink
            if ($response.value) {
                $intuneApps += $response.value
            }
            $nextLink = $response.'@odata.nextLink'
        } while ($nextLink)

        # Return raw Intune data
        return $intuneApps | ConvertTo-Json -Depth 10
    }
    catch {
        Write-Error "Error in Get-IntuneApps: $_"
        throw
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