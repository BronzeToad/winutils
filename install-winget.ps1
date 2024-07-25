[CmdletBinding()]
param (
    [switch]$DisableCleanup,
    [switch]$DebugMode,
    [switch]$Force
)

$ProgressPreference = 'SilentlyContinue'
$ConfirmPreference = 'None'

function Get-TempFolder {
    return [System.IO.Path]::GetTempPath()
}

function Get-OSInfo {
    try {
        $osDetails = Get-CimInstance -ClassName Win32_OperatingSystem
        $architecture = ($osDetails.OSArchitecture -replace "[^\d]").Trim()
        $architecture = if ($architecture -eq "32") { "x32" } elseif ($architecture -eq "64") { "x64" } else { $architecture }

        return [PSCustomObject]@{
            Name           = $osDetails.Caption
            Type           = if ($osDetails.ProductType -eq 1) { "Workstation" } else { "Server" }
            NumericVersion = ($osDetails.Caption -replace "[^\d]").Trim()
            Version        = [System.Environment]::OSVersion.Version
            Architecture   = $architecture
        }
    } catch {
        Write-Error "Unable to get OS version details.`nError: $_"
        exit 1
    }
}

function Write-Section($text) {
    Write-Output "`n$('#' * ($text.Length + 4))`n# $text #`n$('#' * ($text.Length + 4))`n"
}

function Get-WingetDownloadUrl {
    param ([string]$Match)
    $uri = "https://api.github.com/repos/microsoft/winget-cli/releases"
    $releases = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop
    foreach ($release in $releases) {
        if ($release.name -notmatch "preview") {
            $data = $release.assets | Where-Object name -Match $Match
            if ($data) { return $data.browser_download_url }
        }
    }
    $latestRelease = $releases | Select-Object -First 1
    $data = $latestRelease.assets | Where-Object name -Match $Match
    return $data.browser_download_url
}

function Get-WingetStatus {
    return $null -ne (Get-Command -Name winget -ErrorAction SilentlyContinue)
}

function Update-PathEnvironmentVariable {
    param([string]$NewPath)
    foreach ($Level in "Machine", "User") {
        $path = [Environment]::GetEnvironmentVariable("PATH", $Level)
        if (!$path.Contains($NewPath)) {
            $path = ($path + ";" + $NewPath).Split(';') | Select-Object -Unique
            $path = $path -join ';'
            [Environment]::SetEnvironmentVariable("PATH", $path, $Level)
        }
    }
}

function Cleanup {
    param ([string]$Path, [switch]$Recurse)
    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Force -Recurse:$Recurse
    }
}

$osVersion = Get-OSInfo
$arch = $osVersion.Architecture

if (($osVersion.Type -eq "Workstation" -and $osVersion.NumericVersion -lt 10) -or
    ($osVersion.Type -eq "Workstation" -and $osVersion.NumericVersion -eq 10 -and $osVersion.Version.Build -lt 17763) -or
    ($osVersion.Type -eq "Server" -and $osVersion.NumericVersion -lt 2022)) {
    Write-Error "winget is not compatible with this version of Windows."
    exit 1
}

if (Get-WingetStatus -and -not $Force) {
    Write-Output "winget is already installed, exiting..."
    exit 0
}

try {
    Write-Section "Downloading & installing winget..."
    $TempFolder = Get-TempFolder
    $wingetUrl = Get-WingetDownloadUrl -Match "msixbundle"
    $wingetPath = Join-Path -Path $TempFolder -ChildPath "winget.msixbundle"
    $wingetLicenseUrl = Get-WingetDownloadUrl -Match "License1.xml"
    $wingetLicensePath = Join-Path -Path $TempFolder -ChildPath "license1.xml"

    Invoke-WebRequest -Uri $wingetUrl -OutFile $wingetPath
    Invoke-WebRequest -Uri $wingetLicenseUrl -OutFile $wingetLicensePath

    Add-AppxProvisionedPackage -Online -PackagePath $wingetPath -LicensePath $wingetLicensePath -ErrorAction SilentlyContinue | Out-Null
    Write-Output "winget installed successfully."

    if (-not $DisableCleanup) {
        Cleanup -Path $wingetPath
        Cleanup -Path $wingetLicensePath
    }

    $WindowsAppsPath = [IO.Path]::Combine([Environment]::GetEnvironmentVariable("LOCALAPPDATA"), "Microsoft", "WindowsApps")
    Update-PathEnvironmentVariable -NewPath $WindowsAppsPath

    Write-Section "Installation complete!"
    Start-Sleep -Seconds 3

    if (Get-WingetStatus) {
        Write-Output "winget is installed and working now, you can go ahead and use it."
    } else {
        Write-Warning "winget is installed but not detected as a command. Try using winget now. If it doesn't work, wait about 1 minute and try again or restart your computer."
    }
} catch {
    Write-Section "WARNING! An error occurred during installation!"
    Write-Warning "Error: $($_.Exception.Message)"
}