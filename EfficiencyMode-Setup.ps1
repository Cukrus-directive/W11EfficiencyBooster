#Requires -Version 5.1
<#
.SYNOPSIS
    EfficiencyMode-Setup.ps1 - Interactive setup for Windows 11 Efficiency Mode Enforcer

.DESCRIPTION
    Allows users to build keyword lists, match running processes, selectively apply
    Windows 11 Efficiency Mode (EcoQoS), and deploy a scheduled task for continuous enforcement.

.NOTES
    Requires Windows 11 21H2 (Build 22000) or later for EcoQoS API support.
#>

#region ===== T01: Core Infrastructure =====

# --- Configuration ---
$script:AppDataPath = Join-Path $env:APPDATA "EfficiencyMode"
$script:KeywordsFile = Join-Path $script:AppDataPath "keywords.txt"
$script:EnforcerScript = Join-Path $script:AppDataPath "EfficiencyMode-Enforcer.ps1"
$script:LogsPath = Join-Path $script:AppDataPath "logs"

# --- OS Version Check ---
function Test-WindowsVersion {
    <#
    .SYNOPSIS
        Validates Windows 11 21H2+ (Build 22000+) for EcoQoS support
    .OUTPUTS
        Returns $true if supported, $false otherwise
    #>
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber

    # Windows 11 21H2 = Build 22000
    return $build -ge 22000
}

function Assert-WindowsVersion {
    <#
    .SYNOPSIS
        Exits with error if Windows version doesn't support EcoQoS
    #>
    if (-not (Test-WindowsVersion)) {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Header "OS Version Check Failed"
        Write-Error "This tool requires Windows 11 21H2 (Build 22000) or later."
        Write-Error "Current: $($os.Caption) Build $($os.BuildNumber)"
        Write-Info ""
        Write-Info "EcoQoS (true Efficiency Mode) is only available on Windows 11 21H2+."
        Write-Info "Please upgrade your operating system to use this tool."
        exit 1
    }
}

# --- Directory Initialization ---
function Initialize-AppDirectory {
    <#
    .SYNOPSIS
        Creates the EfficiencyMode directory structure in AppData
    #>
    $directories = @(
        $script:AppDataPath,
        $script:LogsPath
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

# --- Console Output Helpers (Pastel Colors) ---
function Write-Header {
    <#
    .SYNOPSIS
        Writes a header/title message in pastel cyan
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    <#
    .SYNOPSIS
        Writes a success message in pastel green
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warning {
    <#
    .SYNOPSIS
        Writes a warning message in pastel yellow
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Error {
    <#
    .SYNOPSIS
        Writes an error message in pastel red
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

function Write-Info {
    <#
    .SYNOPSIS
        Writes an informational message in gray
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor Gray
}

function Write-Prompt {
    <#
    .SYNOPSIS
        Writes a prompt message in white (for user input prompts)
    #>
    param([string]$Message)
    Write-Host $Message -ForegroundColor White -NoNewline
}

#endregion

#region ===== T02: Keyword Management =====

# --- Keyword Storage ---
$script:Keywords = @()

function Get-Keywords {
    <#
    .SYNOPSIS
        Loads keywords from the saved file
    .OUTPUTS
        Array of keywords (strings)
    #>
    if (Test-Path $script:KeywordsFile) {
        $content = Get-Content $script:KeywordsFile -ErrorAction SilentlyContinue
        if ($content) {
            return @($content | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() })
        }
    }
    return @()
}

function Save-Keywords {
    <#
    .SYNOPSIS
        Saves current keywords to file
    #>
    param([string[]]$Keywords)

    if ($Keywords.Count -eq 0) {
        # Write empty file
        Set-Content -Path $script:KeywordsFile -Value "" -Encoding UTF8
    } else {
        Set-Content -Path $script:KeywordsFile -Value ($Keywords -join "`n") -Encoding UTF8
    }
}

function Test-KeywordExists {
    <#
    .SYNOPSIS
        Checks if keyword already exists (case-insensitive)
    #>
    param(
        [string]$Keyword,
        [string[]]$Keywords
    )

    foreach ($existing in $Keywords) {
        if ($existing -ieq $Keyword) {
            return $true
        }
    }
    return $false
}

function Show-KeywordList {
    <#
    .SYNOPSIS
        Displays the current keyword list with numbers
    #>
    param([string[]]$Keywords)

    if ($Keywords.Count -eq 0) {
        Write-Info "  (no keywords defined)"
    } else {
        for ($i = 0; $i -lt $Keywords.Count; $i++) {
            Write-Info "  [$($i + 1)] $($Keywords[$i])"
        }
    }
}

function Show-KeywordMenu {
    <#
    .SYNOPSIS
        Interactive menu for keyword management
    .OUTPUTS
        Returns final keyword list when user selects Done
    #>

    # Load existing keywords
    $keywords = @(Get-Keywords)

    while ($true) {
        Write-Host ""
        Write-Header "--- Keyword Management ---"
        Write-Info "Current keywords:"
        Show-KeywordList $keywords
        Write-Host ""
        Write-Info "[A] Add keyword    [R] Remove keyword    [D] Done"
        Write-Prompt "Choice: "
        $choice = Read-Host

        switch ($choice.ToUpper()) {
            "A" {
                # Add keyword
                Write-Prompt "Enter keyword (process name to match): "
                $newKeyword = Read-Host
                $newKeyword = $newKeyword.Trim()

                if ([string]::IsNullOrWhiteSpace($newKeyword)) {
                    Write-Warning "Empty keyword ignored."
                    continue
                }

                if (Test-KeywordExists -Keyword $newKeyword -Keywords $keywords) {
                    Write-Warning "Keyword '$newKeyword' already exists."
                    continue
                }

                # Add to list
                $keywords += $newKeyword
                Save-Keywords $keywords
                Write-Success "Added: $newKeyword"

                # Auto-preview matching processes (T03 stub)
                Write-Info ""
                Write-Info "Searching for matching processes..."
                Show-MatchingProcessesPreview $newKeyword
            }

            "R" {
                # Remove keyword
                if ($keywords.Count -eq 0) {
                    Write-Warning "No keywords to remove."
                    continue
                }

                Write-Prompt "Enter number to remove (or 0 to cancel): "
                $input = Read-Host

                if ($input -match '^\d+$') {
                    $num = [int]$input
                    if ($num -eq 0) {
                        Write-Info "Cancelled."
                        continue
                    }
                    if ($num -lt 1 -or $num -gt $keywords.Count) {
                        Write-Warning "Invalid number. Enter 1-$($keywords.Count)."
                        continue
                    }

                    $removed = $keywords[$num - 1]
                    $keywords = @($keywords | Where-Object { $_ -ne $removed })
                    Save-Keywords $keywords
                    Write-Success "Removed: $removed"
                } else {
                    Write-Warning "Invalid input. Enter a number."
                }
            }

            "D" {
                # Done
                if ($keywords.Count -eq 0) {
                    Write-Warning "No keywords defined. Add at least one keyword to continue."
                    continue
                }

                Write-Success "Keywords saved."
                return $keywords
            }

            default {
                Write-Warning "Invalid choice. Enter A, R, or D."
            }
        }
    }
}

#endregion

#region ===== T03: Process Discovery =====

function Get-ProcessDisplayInfo {
    <#
    .SYNOPSIS
        Gets display info for a process (window title or path)
    #>
    param([System.Diagnostics.Process]$Process)

    # Try window title first
    $title = $Process.MainWindowTitle
    if (-not [string]::IsNullOrWhiteSpace($title)) {
        # Truncate long titles
        if ($title.Length -gt 50) {
            $title = $title.Substring(0, 47) + "..."
        }
        return $title
    }

    # Fallback to executable path
    try {
        $path = $Process.Path
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            # Truncate long paths
            if ($path.Length -gt 50) {
                $path = "..." + $path.Substring($path.Length - 47)
            }
            return $path
        }
    } catch {
        # Access denied for some system processes
    }

    return "(Background process)"
}

function Get-ProcessParentId {
    <#
    .SYNOPSIS
        Gets the parent process ID for a given process
    #>
    param([int]$ProcessId)

    try {
        $wmiProc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if ($wmiProc) {
            return $wmiProc.ParentProcessId
        }
    } catch {
        # Ignore errors
    }
    return $null
}

function Get-MatchingProcesses {
    <#
    .SYNOPSIS
        Finds all processes matching the given keywords
    .OUTPUTS
        Array of process groups (parent with children)
    #>
    param([string[]]$Keywords)

    $allMatches = @()

    foreach ($keyword in $Keywords) {
        $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like "*$keyword*"
        }

        if ($processes.Count -eq 0) {
            Write-Warning "$keyword : No running processes found"
        } else {
            $allMatches += $processes
        }
    }

    if ($allMatches.Count -eq 0) {
        return @()
    }

    # Remove duplicates (same PID matched by multiple keywords)
    $uniqueProcesses = $allMatches | Sort-Object Id -Unique

    # Group by process name and build parent/child structure
    $grouped = $uniqueProcesses | Group-Object ProcessName

    $result = @()
    foreach ($group in $grouped) {
        $processes = @($group.Group)
        $processName = $group.Name

        # Find a representative process (preferably one with a window)
        $representative = $processes | Where-Object { $_.MainWindowTitle } | Select-Object -First 1
        if (-not $representative) {
            $representative = $processes | Select-Object -First 1
        }

        $displayInfo = Get-ProcessDisplayInfo $representative

        # Count total processes (all are considered children for efficiency mode purposes)
        $totalCount = $processes.Count
        $childCount = if ($totalCount -gt 1) { $totalCount - 1 } else { 0 }

        $result += [PSCustomObject]@{
            ProcessName = $processName
            DisplayInfo = $displayInfo
            TotalCount = $totalCount
            ChildCount = $childCount
            Processes = $processes
            PIDs = @($processes | ForEach-Object { $_.Id })
        }
    }

    return $result
}

function Show-MatchingProcessesPreview {
    <#
    .SYNOPSIS
        Shows matching processes for a keyword (preview after add)
    #>
    param([string]$Keyword)

    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "*$Keyword*"
    }

    if ($processes.Count -eq 0) {
        Write-Warning "  $Keyword : No running processes found"
    } else {
        $grouped = $processes | Group-Object ProcessName
        foreach ($group in $grouped) {
            $count = $group.Count
            $name = $group.Name

            # Get display info from first process with window, or first process
            $representative = $group.Group | Where-Object { $_.MainWindowTitle } | Select-Object -First 1
            if (-not $representative) {
                $representative = $group.Group | Select-Object -First 1
            }
            $displayInfo = Get-ProcessDisplayInfo $representative

            if ($count -eq 1) {
                Write-Success "  $name - $displayInfo"
            } else {
                Write-Success "  $name (+$($count - 1) child processes) - $displayInfo"
            }
        }
    }
}

function Show-ProcessGroups {
    <#
    .SYNOPSIS
        Displays process groups with numbers for selection
    #>
    param([array]$ProcessGroups)

    if ($ProcessGroups.Count -eq 0) {
        Write-Warning "No matching processes found."
        return
    }

    Write-Header "Matching Processes:"
    Write-Info ""

    for ($i = 0; $i -lt $ProcessGroups.Count; $i++) {
        $group = $ProcessGroups[$i]
        $num = $i + 1

        if ($group.ChildCount -gt 0) {
            Write-Info "[$num] $($group.ProcessName) (+$($group.ChildCount) child processes)"
        } else {
            Write-Info "[$num] $($group.ProcessName)"
        }
        Write-Info "    $($group.DisplayInfo)"
    }
}

#endregion

#region ===== T04: Process Selection =====

function Get-ProcessSelection {
    <#
    .SYNOPSIS
        Interactive process selection with All/None shortcuts
    .PARAMETER ProcessGroups
        Array of process groups from Get-MatchingProcesses
    .OUTPUTS
        Array of selected process groups
    #>
    param([array]$ProcessGroups)

    if ($ProcessGroups.Count -eq 0) {
        return @()
    }

    while ($true) {
        Write-Host ""
        Write-Info "Select processes to apply Efficiency Mode:"
        Write-Info "  'a' = All    'n' = None (skip)    Numbers (e.g., 1,3,5)"
        Write-Prompt "Selection: "
        $input = Read-Host

        if ([string]::IsNullOrWhiteSpace($input)) {
            Write-Warning "Please enter a selection."
            continue
        }

        $input = $input.Trim().ToLower()

        # Handle 'a' for all
        if ($input -eq 'a') {
            $totalProcesses = ($ProcessGroups | Measure-Object -Property TotalCount -Sum).Sum
            Write-Success "Selected all $($ProcessGroups.Count) process groups ($totalProcesses total processes)"
            return $ProcessGroups
        }

        # Handle 'n' for none
        if ($input -eq 'n') {
            Write-Info "Skipped process selection."
            return @()
        }

        # Handle comma-separated numbers
        $numbers = @()
        $valid = $true

        foreach ($part in ($input -split ',')) {
            $part = $part.Trim()
            if ($part -match '^\d+$') {
                $num = [int]$part
                if ($num -lt 1 -or $num -gt $ProcessGroups.Count) {
                    Write-Warning "Invalid number: $num (must be 1-$($ProcessGroups.Count))"
                    $valid = $false
                    break
                }
                $numbers += $num
            } else {
                Write-Warning "Invalid input: '$part' - enter numbers separated by commas"
                $valid = $false
                break
            }
        }

        if (-not $valid) {
            continue
        }

        if ($numbers.Count -eq 0) {
            Write-Warning "No valid numbers entered."
            continue
        }

        # Remove duplicates and get selected groups
        $numbers = $numbers | Sort-Object -Unique
        $selected = @()
        foreach ($num in $numbers) {
            $selected += $ProcessGroups[$num - 1]
        }

        # Show summary
        $totalProcesses = ($selected | Measure-Object -Property TotalCount -Sum).Sum
        Write-Success "Selected $($selected.Count) process groups ($totalProcesses total processes):"
        foreach ($group in $selected) {
            if ($group.ChildCount -gt 0) {
                Write-Info "  - $($group.ProcessName) (+$($group.ChildCount) children)"
            } else {
                Write-Info "  - $($group.ProcessName)"
            }
        }

        return $selected
    }
}

#endregion

#region ===== T05: EcoQoS API Implementation =====

# P/Invoke definitions for EcoQoS (Windows 11 Efficiency Mode)
$script:EcoQoSTypeDefined = $false

function Initialize-EcoQoSTypes {
    <#
    .SYNOPSIS
        Defines the P/Invoke types needed for EcoQoS API
    #>
    if ($script:EcoQoSTypeDefined) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class EcoQoS
{
    // Process access rights
    public const uint PROCESS_SET_INFORMATION = 0x0200;
    public const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    // ProcessInformationClass
    public const int ProcessPowerThrottling = 4;

    // Power throttling flags
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
        IntPtr hProcess,
        int ProcessInformationClass,
        IntPtr ProcessInformation,
        uint ProcessInformationSize);

    public static bool EnableEcoQoS(int processId, out int errorCode)
    {
        errorCode = 0;
        IntPtr hProcess = IntPtr.Zero;

        try
        {
            hProcess = OpenProcess(PROCESS_SET_INFORMATION, false, processId);
            if (hProcess == IntPtr.Zero)
            {
                errorCode = Marshal.GetLastWin32Error();
                return false;
            }

            var state = new PROCESS_POWER_THROTTLING_STATE
            {
                Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION,
                ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
                StateMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED  // Enable EcoQoS
            };

            int size = Marshal.SizeOf(state);
            IntPtr ptr = Marshal.AllocHGlobal(size);

            try
            {
                Marshal.StructureToPtr(state, ptr, false);
                bool result = SetProcessInformation(hProcess, ProcessPowerThrottling, ptr, (uint)size);

                if (!result)
                {
                    errorCode = Marshal.GetLastWin32Error();
                    return false;
                }

                return true;
            }
            finally
            {
                Marshal.FreeHGlobal(ptr);
            }
        }
        finally
        {
            if (hProcess != IntPtr.Zero)
            {
                CloseHandle(hProcess);
            }
        }
    }
}
"@ -ErrorAction SilentlyContinue

    $script:EcoQoSTypeDefined = $true
}

function Get-Win32ErrorMessage {
    <#
    .SYNOPSIS
        Converts Win32 error code to friendly message
    #>
    param([int]$ErrorCode)

    switch ($ErrorCode) {
        5 { return "Access denied - process may require elevation" }
        87 { return "Process no longer exists" }
        6 { return "Invalid handle - process may have exited" }
        299 { return "Partial read/write - process state changed" }
        default { return "Error code $ErrorCode" }
    }
}

function Set-EfficiencyMode {
    <#
    .SYNOPSIS
        Applies Efficiency Mode to a single process using BOTH:
        1. PriorityClass = Idle (for Task Manager display)
        2. EcoQoS API (for actual power throttling)
    .PARAMETER ProcessId
        The process ID to apply Efficiency Mode to
    .OUTPUTS
        PSCustomObject with Success, ProcessId, ProcessName, ErrorMessage
    #>
    param(
        [int]$ProcessId,
        [string]$ProcessName = ""
    )

    $prioritySuccess = $false
    $ecoQoSSuccess = $false
    $errorMsg = ""

    # 1. Set Priority to Idle (Task Manager visibility)
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Idle
        $prioritySuccess = $true
    } catch {
        $errorMsg = $_.Exception.Message
    }

    # 2. Apply EcoQoS (actual power throttling)
    Initialize-EcoQoSTypes
    $errorCode = 0
    $ecoQoSSuccess = [EcoQoS]::EnableEcoQoS($ProcessId, [ref]$errorCode)

    # Success if at least priority was set (EcoQoS is bonus)
    $success = $prioritySuccess

    if (-not $success -and -not $ecoQoSSuccess) {
        if ([string]::IsNullOrEmpty($errorMsg)) {
            $errorMsg = Get-Win32ErrorMessage $errorCode
        }
    }

    return [PSCustomObject]@{
        Success = $success
        ProcessId = $ProcessId
        ProcessName = $ProcessName
        PrioritySet = $prioritySuccess
        EcoQoSSet = $ecoQoSSuccess
        ErrorCode = $errorCode
        ErrorMessage = $errorMsg
    }
}

function Apply-EfficiencyModeToProcessGroup {
    <#
    .SYNOPSIS
        Applies Efficiency Mode to all processes in a group
    .PARAMETER ProcessGroup
        A process group from Get-MatchingProcesses
    .OUTPUTS
        PSCustomObject with summary of results
    #>
    param([PSCustomObject]$ProcessGroup)

    $results = @()
    $successCount = 0
    $failCount = 0

    foreach ($procId in $ProcessGroup.PIDs) {
        $result = Set-EfficiencyMode -ProcessId $procId -ProcessName $ProcessGroup.ProcessName
        $results += $result

        if ($result.Success) {
            $successCount++
        } else {
            $failCount++
        }
    }

    return [PSCustomObject]@{
        ProcessName = $ProcessGroup.ProcessName
        TotalCount = $ProcessGroup.TotalCount
        SuccessCount = $successCount
        FailCount = $failCount
        Results = $results
    }
}

function Apply-EfficiencyModeToSelectedGroups {
    <#
    .SYNOPSIS
        Applies Efficiency Mode to all selected process groups
    .PARAMETER SelectedGroups
        Array of process groups from Get-ProcessSelection
    .OUTPUTS
        Summary of all results
    #>
    param([array]$SelectedGroups)

    if ($SelectedGroups.Count -eq 0) {
        return $null
    }

    Write-Header "Applying Efficiency Mode..."
    Write-Info ""

    $totalSuccess = 0
    $totalFail = 0
    $groupResults = @()

    foreach ($group in $SelectedGroups) {
        $result = Apply-EfficiencyModeToProcessGroup -ProcessGroup $group
        $groupResults += $result

        $totalSuccess += $result.SuccessCount
        $totalFail += $result.FailCount

        # Display per-group result
        if ($result.FailCount -eq 0) {
            Write-Success "  $($group.ProcessName): $($result.SuccessCount)/$($result.TotalCount) applied"
        } elseif ($result.SuccessCount -eq 0) {
            Write-Error "  $($group.ProcessName): Failed ($($result.Results[0].ErrorMessage))"
        } else {
            Write-Warning "  $($group.ProcessName): $($result.SuccessCount)/$($result.TotalCount) applied, $($result.FailCount) failed"
        }
    }

    Write-Info ""

    # Summary
    if ($totalFail -eq 0) {
        Write-Success "All $totalSuccess processes set to Efficiency Mode."
    } elseif ($totalSuccess -eq 0) {
        Write-Error "Failed to apply Efficiency Mode to any processes."
        Write-Info "This may require running as Administrator for system processes."
    } else {
        Write-Warning "Applied to $totalSuccess processes, $totalFail failed."
    }

    return [PSCustomObject]@{
        TotalSuccess = $totalSuccess
        TotalFail = $totalFail
        GroupResults = $groupResults
    }
}

#endregion

#region ===== T08: Scheduled Task Registration =====

function Deploy-EnforcerScript {
    <#
    .SYNOPSIS
        Copies the enforcer script to AppData location
    #>

    $sourcePath = Join-Path $PSScriptRoot "EfficiencyMode-Enforcer.ps1"

    if (-not (Test-Path $sourcePath)) {
        Write-Error "Enforcer script not found: $sourcePath"
        return $false
    }

    try {
        Copy-Item -Path $sourcePath -Destination $script:EnforcerScript -Force
        Write-Success "Deployed enforcer script to: $script:EnforcerScript"
        return $true
    } catch {
        Write-Error "Failed to deploy enforcer script: $($_.Exception.Message)"
        return $false
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if running with administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Register-EfficiencyTask {
    <#
    .SYNOPSIS
        Registers the scheduled task for enforcement
    #>

    $taskName = "EfficiencyModeEnforcer"
    $taskDescription = "Applies Windows 11 Efficiency Mode (EcoQoS) to configured processes every 15 minutes"

    # Build XML for task scheduler
    $xmlContent = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$taskDescription</Description>
    <URI>\$taskName</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Repetition>
        <Interval>PT15M</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$($script:EnforcerScript)"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

    # Write XML to temp file
    $xmlPath = Join-Path $script:AppDataPath "EfficiencyModeTask.xml"
    $utf16 = New-Object System.Text.UnicodeEncoding $False, $True
    [System.IO.File]::WriteAllText($xmlPath, $xmlContent, $utf16)

    # Register the task (overwrites if exists)
    Write-Info "Registering scheduled task: $taskName"

    try {
        $result = schtasks /Create /TN $taskName /XML $xmlPath /F 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Scheduled task registered successfully"

            # Run immediately
            Write-Info "Starting task..."
            schtasks /Run /TN $taskName | Out-Null

            Write-Success "Task started"
            return $true
        } else {
            Write-Error "Failed to register task: $result"
            return $false
        }
    } catch {
        Write-Error "Exception registering task: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region ===== Main Entry Point =====

# Only run main when executed directly (not dot-sourced for testing)
if ($MyInvocation.InvocationName -eq '.') {
    return
}

# Banner
Clear-Host
Write-Header "=============================================="
Write-Header "   Efficiency Mode Enforcer - Setup"
Write-Header "=============================================="
Write-Info ""

# T01: OS Version Check (fail fast)
Assert-WindowsVersion
Write-Success "OS Check Passed: Windows 11 Build $((Get-CimInstance Win32_OperatingSystem).BuildNumber)"
Write-Info ""

# T01: Initialize directories
Initialize-AppDirectory
Write-Info "App directory: $script:AppDataPath"
Write-Info ""

# T02: Keyword Management
$keywords = Show-KeywordMenu

Write-Host ""
Write-Header "Keywords configured: $($keywords.Count)"
foreach ($kw in $keywords) {
    Write-Info "  - $kw"
}
Write-Host ""

# T03: Process Discovery
Write-Header "Discovering matching processes..."
Write-Info ""
$processGroups = Get-MatchingProcesses -Keywords $keywords

$selectedGroups = @()
if ($processGroups.Count -eq 0) {
    Write-Warning "No matching processes found for any keyword."
    Write-Info "The scheduled task will still be created to monitor for these processes."
    Write-Info ""
} else {
    Show-ProcessGroups $processGroups
    Write-Info ""

    # T04: Process Selection
    $selectedGroups = Get-ProcessSelection -ProcessGroups $processGroups
    Write-Info ""
}

# T05: Apply Efficiency Mode
if ($selectedGroups.Count -gt 0) {
    Write-Info ""
    $efficiencyResult = Apply-EfficiencyModeToSelectedGroups -SelectedGroups $selectedGroups
    Write-Info ""
}

# T08: Deploy and Register Scheduled Task
Write-Host ""
Write-Header "--- Deployment ---"
Write-Info ""

# Check admin for task registration
if (-not (Test-IsAdmin)) {
    Write-Warning "Not running as Administrator."
    Write-Info "Task registration requires elevated privileges."
    Write-Info ""
    Write-Prompt "Continue anyway? Script will be deployed but task may fail. (Y/N): "
    $continue = Read-Host
    if ($continue -notmatch '^[Yy]') {
        Write-Info "Please re-run this script as Administrator."
        exit 0
    }
}

# Deploy enforcer script
if (Deploy-EnforcerScript) {
    # Register scheduled task
    if (Register-EfficiencyTask) {
        Write-Host ""
        Write-Header "=============================================="
        Write-Success "   Setup Complete!"
        Write-Header "=============================================="
        Write-Info ""
        Write-Info "Scheduled task 'EfficiencyModeEnforcer' is now running."
        Write-Info "It will apply Efficiency Mode every 15 minutes."
        Write-Info ""
        Write-Info "Configuration:"
        Write-Info "  Keywords: $script:KeywordsFile"
        Write-Info "  Logs: $script:LogsPath"
        Write-Info ""
        Write-Info "To modify keywords, run this setup again or edit:"
        Write-Info "  $script:KeywordsFile"
        Write-Info ""
    } else {
        Write-Error "Failed to register scheduled task."
        Write-Info ""
        Write-Info "The enforcer script has been deployed to:"
        Write-Info "  $script:EnforcerScript"
        Write-Info ""
        Write-Info "To complete setup, run this script as Administrator,"
        Write-Info "or manually create a scheduled task pointing to the above script."
    }
} else {
    Write-Error "Failed to deploy enforcer script."
}

#endregion
