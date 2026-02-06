# Windows 11 Efficiency Mode Enforcer

Applies Efficiency Mode to specified processes automatically. This is to leverage new intel P,E,LPE cores as well as work with Ryzen's latest power plans.

## Requirements

- Windows 11 21H2 or later
- Administrator privileges

## Usage

1. Run `Run-EfficiencyMode-Setup.bat` as Administrator
2. Add keywords to match process names (e.g., `qualys`, `discord`)
3. Select which matched processes to throttle
4. Done - the scheduled task handles the rest

## Files

| File | Purpose |
|------|---------|
| `Run-EfficiencyMode-Setup.bat` | Launcher with auto-elevation |
| `EfficiencyMode-Setup.ps1` | Interactive setup and configuration |
| `EfficiencyMode-Enforcer.ps1` | Scheduled task script (runs every hour) |

## Config

After setup, files are stored in `%APPDATA%\EfficiencyMode\`:

- `keywords.txt` - Edit to add/remove process keywords
- `logs\` - Daily logs with 7-day retention

## Innerworkings

Matches running processes against your keywords and applies:
- **Idle priority** - reduces CPU scheduling priority
- **EcoQoS** - enables Windows power throttling

The scheduled task re-applies every hour to catch new processes.
