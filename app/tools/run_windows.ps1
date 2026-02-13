param(
  [string]$Device = "windows",
  [string]$EnvFile = "env.json"
)

$ErrorActionPreference = "Stop"

& "$PSScriptRoot\\ensure_firebase_cpp_sdk.ps1" -SetEnv | Out-Null

Push-Location (Join-Path $PSScriptRoot "..")
try {
  $args = @("run", "-d", $Device)
  if (Test-Path $EnvFile) {
    $args += "--dart-define-from-file=$EnvFile"
  }
  flutter @args
}
finally {
  Pop-Location
}

