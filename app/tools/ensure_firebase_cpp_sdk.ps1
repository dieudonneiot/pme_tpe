param(
  [string]$Version = "12.7.0",
  [string]$CacheRoot = "",
  [switch]$SetEnv
)

$ErrorActionPreference = "Stop"

function Get-DefaultCacheRoot([string]$ver) {
  if (-not $env:LOCALAPPDATA) {
    throw "LOCALAPPDATA is not set; provide -CacheRoot."
  }
  return (Join-Path $env:LOCALAPPDATA "PME_TPE\\firebase_cpp_sdk_windows_$ver")
}

if ([string]::IsNullOrWhiteSpace($CacheRoot)) {
  $CacheRoot = Get-DefaultCacheRoot -ver $Version
}

$sdkDir = Join-Path $CacheRoot "firebase_cpp_sdk_windows"
$versionHeader = Join-Path $sdkDir "include\\firebase\\version.h"

if (-not (Test-Path $versionHeader)) {
  New-Item -ItemType Directory -Force -Path $CacheRoot | Out-Null

  $projectSdkDir = Join-Path $PSScriptRoot "..\\build\\windows\\x64\\extracted\\firebase_cpp_sdk_windows"
  $projectVersionHeader = Join-Path $projectSdkDir "include\\firebase\\version.h"

  if (Test-Path $projectVersionHeader) {
    Write-Host "Found SDK in project build cache; copying to user cache..."
    cmd /c "robocopy ""$projectSdkDir"" ""$sdkDir"" /E /NFL /NDL /NJH /NJS /NP" | Out-Null
  }
  else {
    $zip = Join-Path $CacheRoot "firebase_cpp_sdk_windows_$Version.zip"
    $url = "https://dl.google.com/firebase/sdk/cpp/firebase_cpp_sdk_windows_$Version.zip"

    if (-not (Test-Path $zip)) {
      Write-Host "Downloading Firebase C++ SDK $Version (one-time)..."
      Start-BitsTransfer -Source $url -Destination $zip -Priority Foreground -TransferType Download
    }
    else {
      Write-Host "Using cached SDK zip: $zip"
    }

    if (Test-Path $sdkDir) {
      Remove-Item -Recurse -Force $sdkDir
    }

    $tmpExtract = Join-Path $CacheRoot "extracted_tmp"
    if (Test-Path $tmpExtract) {
      Remove-Item -Recurse -Force $tmpExtract
    }
    New-Item -ItemType Directory -Force -Path $tmpExtract | Out-Null

    Write-Host "Extracting SDK..."
    Expand-Archive -LiteralPath $zip -DestinationPath $tmpExtract -Force

    $extractedSdk = Join-Path $tmpExtract "firebase_cpp_sdk_windows"
    if (-not (Test-Path (Join-Path $extractedSdk "include\\firebase\\version.h"))) {
      throw "Extraction did not produce firebase_cpp_sdk_windows/include/firebase/version.h."
    }

    Move-Item -Force $extractedSdk $sdkDir
    Remove-Item -Recurse -Force $tmpExtract
  }
}

if (-not (Test-Path $versionHeader)) {
  throw "Firebase C++ SDK not found after setup: $versionHeader"
}

if ($SetEnv) {
  $env:FIREBASE_CPP_SDK_DIR = $sdkDir
  Write-Host "Set FIREBASE_CPP_SDK_DIR=$sdkDir"
}

Write-Output $sdkDir

