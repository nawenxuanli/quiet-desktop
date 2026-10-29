# Quiet Desktop for Windows

A native Windows edition of Quiet Desktop, built with WPF and .NET 10. The macOS app remains available separately.

## Features

- Clock, date, app search, and editable/reorderable Within Reach shortcuts.
- Start Menu shortcut discovery and Explorer folder shortcuts.
- Notes saved on this PC; no sign-in required.
- Personal photo selection, rounded edge-to-edge display, zoom, and crop positioning.
- System, Light, and Dark themes. System follows the Windows app-mode setting.
- Ctrl K to search, F11 for full screen, Escape to leave full screen, Alt F4 to quit.

The Windows app reads user and common Start Menu shortcuts. It is a desktop companion; it does not replace Explorer, change wallpaper, modify the taskbar, or configure itself to launch at login. Restart the app to refresh newly installed app shortcuts.

## Requirements and installation

Windows 10 version 2004 or later / Windows 11, x64. The portable ZIP includes the .NET runtime. Extract the entire ZIP into a folder, then open QuietDesktop.exe. Keep the bundled DLLs with the executable. This standalone build is not Authenticode-signed and may prompt Windows reputation checks. Do not disable Windows security protections.

MSIX packaging is provided for Microsoft Store submission. Its identity must come from the reserved Quiet Desktop product in Partner Center. An unsigned Store-upload MSIX is not a general-purpose sideload installer; the Store signs accepted packages.

## Build and validate on Windows

Install the .NET 10 SDK, then run PowerShell:

```powershell
./WindowsBuild.ps1
```

The script publishes a self-contained x64 app, runs a native window smoke check and settings/crop checks, renders a preview, and creates the portable ZIP in windows-build/.

The GitHub workflow **Windows build and Store package** runs the same process on windows-latest. Local cross-compilation on macOS verifies compilation only; it does not prove Windows runtime or Store certification.

## Store packaging

Reserve Quiet Desktop in Partner Center, then set these repository secrets using the exact assigned identity:

- QUIET_STORE_PACKAGE_NAME
- QUIET_STORE_PUBLISHER
- QUIET_STORE_PUBLISHER_DISPLAY_NAME

Run the Windows workflow with **store_package** enabled. It builds an MSIX and attempts Windows App Certification Kit checks. It fails if the identity, certification tools, or certification result are unavailable. Review the resulting report before submission. Do not reuse Orbit's package identity.

## Data and privacy

Notes, appearance, favorites, crop settings, and a resized photo copy are stored under the current user's LocalApplicationData/QuietDesktop folder (Windows may manage this location for Store packages). Data is not encrypted by this app. No telemetry, advertising, accounts, or direct network requests are included. Windows or applications you launch can use their normal connections. The original photo file is never edited. See [Privacy policy](PRIVACY.md).

## Validation status

The Windows source compiles on the development Mac. Windows runner checks and Store certification must be verified independently from their actual results; no Store approval is implied by the presence of these packaging scripts.
