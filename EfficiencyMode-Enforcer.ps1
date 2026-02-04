#Requires -Version 5.1
<#
.SYNOPSIS
    EfficiencyMode-Enforcer.ps1 - Scheduled task script for Windows 11 Efficiency Mode

.DESCRIPTION
    Runs silently on schedule to apply EcoQoS (Efficiency Mode) to processes
    matching saved keywords. Logs all runs with daily rotation.

.NOTES
    This script is meant to be run by Task Scheduler, not interactively.
    Exit codes: 0 = success/partial, 1 = complete failure (triggers toast)
#>

#region ===== Configuration =====

$script:AppDataPath = Join-Path $env:APPDATA "EfficiencyMode"
$script:KeywordsFile = Join-Path $script:AppDataPath "keywords.txt"
$script:LogsPath = Join-Path $script:AppDataPath "logs"
$script:LogRetentionDays = 7

#endregion

#region ===== Logging =====

function Get-LogFilePath {
    $date = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $script:LogsPath "EfficiencyMode-$date.log"
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"

    # Ensure logs directory exists
    if (-not (Test-Path $script:LogsPath)) {
        New-Item -ItemType Directory -Path $script:LogsPath -Force | Out-Null
    }

    $logFile = Get-LogFilePath
    Add-Content -Path $logFile -Value $logLine -Encoding UTF8
}

function Remove-OldLogs {
    <#
    .SYNOPSIS
        Removes log files older than retention period
    #>
    if (-not (Test-Path $script:LogsPath)) {
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$script:LogRetentionDays)

    Get-ChildItem -Path $script:LogsPath -Filter "EfficiencyMode-*.log" | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Log "Removed old log: $($_.Name)" "INFO"
    }
}

#endregion

#region ===== EcoQoS API =====

$script:EcoQoSTypeDefined = $false

function Initialize-EcoQoSTypes {
    if ($script:EcoQoSTypeDefined) { return }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class EcoQoS
{
    public const uint PROCESS_SET_INFORMATION = 0x0200;
    public const int ProcessPowerThrottling = 4;
    public const uint PROCESS_POWER_THROTTLING_CURRENT_VERSION = 1;
    public const uint PROCESS_POWER_THROTTLING_EXECUTION_SPEED = 0x1;

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_POWER_THROTTLING_STATE
    {
        public uint Version;
        public uint ControlMask;
        public uint StateMask;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetProcessInformation(
        IntPtr hProcess, int ProcessInformationClass,
        IntPtr ProcessInformation, uint ProcessInformationSize);

    public static bool EnableEcoQoS(int processId, out int errorCode)
    {
        errorCode = 0;
        IntPtr hProcess = IntPtr.Zero;
        try
        {
            hProcess = OpenProcess(PROCESS_SET_INFORMATION, false, processId);
            if (hProcess == IntPtr.Zero) { errorCode = Marshal.GetLastWin32Error(); return false; }

            var state = new PROCESS_POWER_THROTTLING_STATE {
                Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION,
                ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
                StateMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED
            };

            int size = Marshal.SizeOf(state);
            IntPtr ptr = Marshal.AllocHGlobal(size);
            try
            {
                Marshal.StructureToPtr(state, ptr, false);
                bool result = SetProcessInformation(hProcess, ProcessPowerThrottling, ptr, (uint)size);
                if (!result) { errorCode = Marshal.GetLastWin32Error(); return false; }
                return true;
            }
            finally { Marshal.FreeHGlobal(ptr); }
        }
        finally { if (hProcess != IntPtr.Zero) CloseHandle(hProcess); }
    }
}
"@ -ErrorAction SilentlyContinue

    $script:EcoQoSTypeDefined = $true
}

#endregion

#region ===== Efficiency Mode =====

function Set-EfficiencyMode {
    <#
    .SYNOPSIS
        Applies Efficiency Mode using BOTH Priority (Idle) and EcoQoS API
    #>
    param(
        [int]$ProcessId,
        [string]$ProcessName = ""
    )

    $prioritySuccess = $false
    $ecoQoSSuccess = $false

    # 1. Set Priority to Idle (Task Manager visibility)
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle
        $prioritySuccess = $true
    } catch { }

    # 2. Apply EcoQoS (actual power throttling)
    Initialize-EcoQoSTypes
    $errorCode = 0
    $ecoQoSSuccess = [EcoQoS]::EnableEcoQoS($ProcessId, [ref]$errorCode)

    # Success if at least priority was set
    return $prioritySuccess
}

#endregion

#region ===== Process Discovery =====

function Get-MatchingProcesses {
    param([string[]]$Keywords)

    $allMatches = @()

    foreach ($keyword in $Keywords) {
        $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like "*$keyword*"
        }

        if ($processes) {
            $allMatches += $processes
        }
    }

    # Remove duplicates
    return $allMatches | Sort-Object Id -Unique
}

#endregion

#region ===== T07: Toast Notifications =====

function Show-FailureToast {
    <#
    .SYNOPSIS
        Shows Windows toast notification on failure
    .PARAMETER Message
        The message to display in the toast
    #>
    param([string]$Message)

    Write-Log "Showing failure toast: $Message" "ERROR"

    $logFile = Get-LogFilePath

    # Try BurntToast first (if installed)
    try {
        $burntToast = Get-Module -ListAvailable -Name BurntToast -ErrorAction SilentlyContinue
        if ($burntToast) {
            Import-Module BurntToast -ErrorAction Stop

            # Create toast with click action to open log
            $clickAction = New-BTAction -Arguments "file://$logFile" -ActivationType Protocol
            New-BurntToastNotification `
                -Text "Efficiency Mode Enforcer", $Message, "Click to view log" `
                -AppLogo $null `
                -Actions $clickAction `
                -ErrorAction Stop

            Write-Log "Toast shown via BurntToast" "INFO"
            return
        }
    } catch {
        Write-Log "BurntToast failed: $($_.Exception.Message)" "WARN"
    }

    # Fallback to native Windows toast via PowerShell
    try {
        # Load required assemblies
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $appId = "EfficiencyModeEnforcer"

        # Toast XML template with action
        $toastXml = @"
<toast activationType="protocol" launch="file://$logFile">
    <visual>
        <binding template="ToastGeneric">
            <text>Efficiency Mode Enforcer</text>
            <text>$Message</text>
            <text>Click to view log</text>
        </binding>
    </visual>
    <actions>
        <action content="Open Log" activationType="protocol" arguments="file://$logFile"/>
        <action content="Dismiss" activationType="system" arguments="dismiss"/>
    </actions>
</toast>
"@

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($toastXml)

        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)

        Write-Log "Toast shown via native API" "INFO"
    } catch {
        Write-Log "Native toast failed: $($_.Exception.Message)" "WARN"

        # Last resort: Just log and continue (no toast available)
        Write-Log "Toast notification unavailable - failure logged only" "WARN"
    }
}

#endregion

#region ===== Main Execution =====

# Start logging
Write-Log "========== Enforcement Run Started ==========" "INFO"

# Clean up old logs
Remove-OldLogs

# Check keywords file
if (-not (Test-Path $script:KeywordsFile)) {
    Write-Log "Keywords file not found: $script:KeywordsFile" "WARN"
    Write-Log "No keywords configured. Exiting." "INFO"
    exit 0
}

# Load keywords
$keywords = @(Get-Content $script:KeywordsFile -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })

if ($keywords.Count -eq 0) {
    Write-Log "Keywords file is empty." "WARN"
    Write-Log "No keywords configured. Exiting." "INFO"
    exit 0
}

Write-Log "Loaded $($keywords.Count) keywords: $($keywords -join ', ')" "INFO"

# Find matching processes
$processes = Get-MatchingProcesses -Keywords $keywords

if ($processes.Count -eq 0) {
    Write-Log "No matching processes found." "INFO"
    Write-Log "========== Enforcement Run Complete ==========" "INFO"
    exit 0
}

Write-Log "Found $($processes.Count) matching processes" "INFO"

# Apply Efficiency Mode (Idle priority) to all matched processes
$successCount = 0
$failCount = 0

foreach ($proc in $processes) {
    $success = Set-EfficiencyMode -ProcessId $proc.Id -ProcessName $proc.ProcessName

    if ($success) {
        $successCount++
        Write-Log "Applied Efficiency Mode: $($proc.ProcessName) (PID: $($proc.Id))" "INFO"
    } else {
        $failCount++
        Write-Log "Failed: $($proc.ProcessName) (PID: $($proc.Id))" "WARN"
    }
}

# Summary
Write-Log "Results: $successCount applied, $failCount failed" "INFO"
Write-Log "========== Enforcement Run Complete ==========" "INFO"

# Determine exit code and toast
if ($processes.Count -gt 0 -and $successCount -eq 0) {
    # Complete failure - all processes failed
    Show-FailureToast "Failed to apply efficiency mode to any processes"
    exit 1
}

exit 0

#endregion
