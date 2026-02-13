# flutter_application_1

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Windows + Firebase C++ SDK (firebase_core)

Some FlutterFire plugins on Windows require the Firebase C++ SDK (large download). To avoid downloading it into the repo `build/` folder, use:

- `powershell -ExecutionPolicy Bypass -File .\\tools\\build_windows.ps1`
- `powershell -ExecutionPolicy Bypass -File .\\tools\\run_windows.ps1`

This script caches the SDK under `%LOCALAPPDATA%\\PME_TPE\\firebase_cpp_sdk_windows_12.7.0\\firebase_cpp_sdk_windows` and sets `FIREBASE_CPP_SDK_DIR` for the build.
