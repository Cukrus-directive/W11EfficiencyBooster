# Deprecated Legacy Code

These PowerShell scripts are the original implementation, now replaced by the C# system tray application.

## Why deprecated?

- PowerShell window flashes briefly when Task Scheduler runs the script
- Multiple files to manage/copy between machines
- Console-based setup is not user-friendly

## Use the new version instead

See the main [README](../README.md) for the new single-file tray application.

## Files

- `EfficiencyMode-Setup.ps1` - Interactive setup wizard
- `EfficiencyMode-Enforcer.ps1` - Scheduled task script
- `Run-EfficiencyMode-Setup.bat` - Entry point (auto-elevates)
