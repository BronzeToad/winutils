# Change execution policy for the current process
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# Define the path to your local winutils package
$winutilsPath = "C:\projects\winutils"

# Define the path to the winget installation script in your package
$wingetInstallScriptPath = Join-Path $winutilsPath "install-winget.ps1"

# Check if the winget installation script exists
if (Test-Path $wingetInstallScriptPath) {
    # Execute the winget installation script
    & $wingetInstallScriptPath
} else {
    Write-Host "Winget installation script not found at: $wingetInstallScriptPath" -ForegroundColor Red
    exit 1
}

# Pause to keep the window open
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")