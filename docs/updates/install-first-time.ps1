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

Write-Host ""
Write-Host "Install completed successfully." -ForegroundColor Green
Write-Host ("MSIX: " + $msixName)
