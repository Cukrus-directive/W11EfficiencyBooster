# Windows 11 Efficiency Booster

System tray application that automatically applies Efficiency Mode (EcoQoS) to processes matching configured keywords. Designed for Intel P/E-core and AMD Ryzen architectures to throttle non-critical applications.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D4?style=flat&logo=windows11&logoColor=white)
![.NET 10](https://img.shields.io/badge/.NET%2010-512BD4?style=flat&logo=dotnet&logoColor=white)

## Features

- **System Tray** - Always accessible, minimal footprint
- **Single .exe** - No installation required, just copy and run
- **Automatic Enforcement** - Runs hourly in the background
- **Keyword Matching** - Configure process name patterns to throttle
- **Start with Windows** - Optional automatic startup
- **No Console Flash** - Pure native app, no PowerShell window

## References

Thiese features are questionably documented, for that reason, I've extracted a few critical pieces from Microsoft 

https://www.techrepublic.com/article/ecoqos-gives-windows-11-apps-better-battery-life/
https://devblogs.microsoft.com/performance-diagnostics/introducing-ecoqos/
https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessinformation
https://devblogs.microsoft.com/performance-diagnostics/reduce-process-interference-with-task-manager-efficiency-mode/

| Metric | Value | Context |
|--------|-------|---------|
| **EcoQoS CPU power reduction** | **Up to 90%** | Per-process power draw |
| **EcoQoS energy to complete same work** | **< 50%** of normal | Even accounting for longer execution time |
| **Foreground responsiveness gain** | **14–76%** improvement | Background processes no longer competing |
| **Typical EcoQoS frequency cap** | **~1.0–1.6 GHz** | vs 4.5+ GHz turbo = massive power savings |
| **Power vs frequency relationship** | **Power ∝ frequency³** | Small freq drops = cubic power savings |
| **Meteor Lake LP E-core savings** | **~30%** reduction | Compute tile can fully power off |
| **Windows Energy Saver battery gain** | **Up to 14%** | Cumulative across background apps |
| **Edge Efficiency Mode battery gain** | **+14 min** measured | Single app, single laptop |
| **E-core routing on hybrid CPUs** | **Automatic** | Thread Director + EcoQoS cooperate |
| **Child processes not inherited** | **By design** | Games launched by Steam won't be throttled |
| **Thread Director workload classes** | **4 classes** | Hardware ML model classifies in real-time |

## Download

Get the latest `EfficiencyBooster.exe` from [Releases](../../releases). Self-contained — no .NET runtime needed.

## Requirements

- Windows 11 21H2 (Build 22000) or later

## Security

Runs as a normal user by default — no UAC prompt, no admin required. This covers most user-level processes. For full coverage (SYSTEM/service processes), enable **Run as Admin (Full Coverage)** in the tray menu, which creates a scheduled task with elevated privileges (one-time UAC prompt). The app never phones home and stores settings locally in `%APPDATA%`.

## Usage

1. Run `EfficiencyBooster.exe`
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
├── Enabled                        [✓]
├── Start with Windows             [✓]
├── Run as Admin (Full Coverage)   [ ]
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


## Configuration

Settings stored in `%APPDATA%\EfficiencyBooster\settings.json`:

```json
{
  "keywords": ["steam", "asus", "searchindex"],
  "startWithWindows": true,
  "intervalMinutes": 60,
  "enforcementEnabled": true
}
```

## Legacy Version

The original PowerShell-based implementation is in [`deprecated_legacy_code/`](deprecated_legacy_code/).
