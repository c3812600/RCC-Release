#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$BaseUri = "https://c3812600.github.io/RCC-Release/updates",
    [string]$CertFileName = "RCC-msix.cer",
    [string]$AppInstallerFileName = "ControlCommand.appinstaller"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        return
    }

    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-BaseUri', ('"{0}"' -f $BaseUri),
        '-CertFileName', ('"{0}"' -f $CertFileName),
        '-AppInstallerFileName', ('"{0}"' -f $AppInstallerFileName)
    )
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($argList -join ' ')
    exit
}

function Get-RemoteFile {
    param(
        [string]$Url,
        [string]$DestinationPath
    )

    Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing
}

function Get-MsixDownloadUrl {
    param([string]$AppInstallerPath)

    [xml]$xml = Get-Content -Path $AppInstallerPath -Raw -Encoding UTF8
    $mainPackage = $xml.AppInstaller.MainPackage
    if (-not $mainPackage) {
        throw "MainPackage not found in appinstaller file."
    }

    $uri = [string]$mainPackage.Uri
    if (-not $uri) {
        throw "MSIX Uri not found in appinstaller file."
    }

    return $uri
}

Ensure-Administrator

$base = $BaseUri.TrimEnd('/')
$tempRoot = Join-Path $env:TEMP "RCC-FirstInstall"
$certPath = Join-Path $tempRoot $CertFileName
$appInstallerPath = Join-Path $tempRoot $AppInstallerFileName

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$certUrl = "$base/$CertFileName"
$appInstallerUrl = "$base/$AppInstallerFileName"

Write-Host "Downloading certificate..." -ForegroundColor Cyan
Get-RemoteFile -Url $certUrl -DestinationPath $certPath

Write-Host "Importing certificate..." -ForegroundColor Cyan
Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null

Write-Host "Downloading installer metadata..." -ForegroundColor Cyan
Get-RemoteFile -Url $appInstallerUrl -DestinationPath $appInstallerPath
$msixUrl = Get-MsixDownloadUrl -AppInstallerPath $appInstallerPath
$msixName = Split-Path -Leaf $msixUrl
$msixPath = Join-Path $tempRoot $msixName

Write-Host "Downloading MSIX package..." -ForegroundColor Cyan
Get-RemoteFile -Url $msixUrl -DestinationPath $msixPath
Unblock-File -Path $msixPath -ErrorAction SilentlyContinue

Write-Host "Installing ControlCommand..." -ForegroundColor Cyan
Add-AppxPackage -Path $msixPath -ForceApplicationShutdown

# --- Create desktop shortcut ---
Write-Host "Creating desktop shortcut..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms

$desktopPath = [Environment]::GetFolderPath("Desktop")
$lnkPath = Join-Path $desktopPath "ControlCommand.lnk"
$desktopShortcutCreated = $false

# Wait for system to register the MSIX package
Start-Sleep -Seconds 3

# Get the installed package info via Get-AppxPackage (more reliable than shell:AppsFolder)
$pkg = Get-AppxPackage -Name "RCC.ControlCommand" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($pkg) {
    # AppUserModelID format: {PackageFamilyName}!{ApplicationId}
    $appUserModelId = "$($pkg.PackageFamilyName)!ControlCommand"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnkPath)
    $shortcut.TargetPath = "explorer.exe"
    $shortcut.Arguments = "shell:AppsFolder\$appUserModelId"
    $shortcut.WorkingDirectory = $desktopPath
    $shortcut.Description = "ControlCommand"
    $shortcut.Save()
    $desktopShortcutCreated = $true
    Write-Host "Desktop shortcut created: $lnkPath" -ForegroundColor Green
} else {
    Write-Host "Could not find installed package, skipping shortcut." -ForegroundColor Yellow
}

# --- Completion dialog with Launch button ---
Write-Host ""
Write-Host "Install completed successfully." -ForegroundColor Green
Write-Host ("MSIX: " + $msixName)

$msg = if ($desktopShortcutCreated) {
    "ControlCommand installed successfully!`n`nA desktop shortcut has been created.`n`nClick 'Yes' to launch now, or 'No' to close."
} else {
    "ControlCommand installed successfully!`n`nClick 'Yes' to launch now, or 'No' to close."
}

$result = [System.Windows.Forms.MessageBox]::Show(
    $msg,
    "Installation Complete",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

if ($result -eq [System.Windows.Forms.DialogResult]::Yes -and $pkg) {
    Start-Process "explorer.exe" "shell:AppsFolder\$($pkg.PackageFamilyName)!ControlCommand"
}
