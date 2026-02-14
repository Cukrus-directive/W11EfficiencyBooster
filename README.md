# Windows 11 Efficiency Booster

System tray application that automatically applies Efficiency Mode (EcoQoS) to processes matching configured keywords. Designed for Intel P/E-core and AMD Ryzen architectures to throttle non-critical applications.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?style=flat&logo=windows11&logoColor=white)
![.NET 10](https://img.shields.io/badge/.NET%2010-512BD4?style=flat&logo=dotnet&logoColor=white)

## Features

- **System Tray Icon** - Always accessible, minimal footprint
- **Single .exe** - No installation required, just copy and run
- **Automatic Enforcement** - Runs hourly in the background
- **Keyword Matching** - Configure process name patterns to throttle
- **Start with Windows** - Optional automatic startup
- **No Console Flash** - Pure native app, no PowerShell window

## Download

Get the latest `EfficiencyBooster.exe` from [Releases](../../releases).

## Requirements

- Windows 11 21H2 (Build 22000) or later
- Administrator privileges

## Usage

1. Run `EfficiencyBooster.exe` as Administrator
2. Right-click the tray icon → **Edit Keywords...**
3. Add keywords matching processes to throttle (e.g., `chrome`, `slack`, `teams`)
4. Click **Run Now** or wait for hourly enforcement

## Tray Menu

```
Right-click menu:
├── Status: Running (12 processes throttled)
├── ─────────────────
├── Run Now
├── Edit Keywords...
├── View Logs...
├── ─────────────────
├── Enabled             [✓]
├── Start with Windows  [✓]
├── ─────────────────
└── Exit
```

## How It Works

Matches running processes against your keywords and applies:
- **Idle Priority** - Reduces CPU scheduling priority
- **EcoQoS API** - Enables Windows 11 power throttling (routes to E-cores)

The background timer re-applies every hour to catch newly launched processes.

## Building from Source

Requires [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0).

```batch
# Build
build.bat

# Publish single-file .exe
publish.bat
```

Output: `publish/EfficiencyBooster.exe`

## Configuration

Settings stored in `%APPDATA%\EfficiencyBooster\settings.json`:

```json
{
  "keywords": ["chrome", "slack", "teams"],
  "startWithWindows": true,
  "intervalMinutes": 60,
  "enforcementEnabled": true
}
```

## Legacy Version

The original PowerShell-based implementation is in [`deprecated_legacy_code/`](deprecated_legacy_code/).
