param(
  [string]$FirebaseSdkVersion = "12.7.0"
)

$ErrorActionPreference = "Stop"

$sdkDir = & "$PSScriptRoot\\ensure_firebase_cpp_sdk.ps1" -Version $FirebaseSdkVersion -SetEnv
Write-Host "Using Firebase C++ SDK: $sdkDir"

Push-Location (Join-Path $PSScriptRoot "..")
try {
  flutter build windows
}
finally {
  Pop-Location
}

