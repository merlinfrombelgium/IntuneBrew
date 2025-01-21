function Say-Hello {
    param(
        [string]$name = "World"
    )
    return "Hello, $name from PowerShell! Time is: $(Get-Date -Format 'HH:mm:ss')"
} 