using System.Runtime.InteropServices;

namespace EfficiencyBooster.Services;

/// <summary>
/// Provides P/Invoke wrappers for Windows EcoQoS (Efficiency Mode) API.
/// Requires Windows 11 21H2 (Build 22000) or later.
/// </summary>
public static class EcoQosService
{
    #region Constants

    private const uint PROCESS_SET_INFORMATION = 0x0200;
    private const int ProcessPowerThrottling = 4;
    private const uint PROCESS_POWER_THROTTLING_CURRENT_VERSION = 1;
    private const uint PROCESS_POWER_THROTTLING_EXECUTION_SPEED = 0x1;

    #endregion

    #region Structures

    [StructLayout(LayoutKind.Sequential)]
    private struct PROCESS_POWER_THROTTLING_STATE
    {
        public uint Version;
        public uint ControlMask;
        public uint StateMask;
    }

    #endregion

    #region P/Invoke

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetProcessInformation(
        IntPtr hProcess,
        int ProcessInformationClass,
        IntPtr ProcessInformation,
        uint ProcessInformationSize);

    #endregion

    /// <summary>
    /// Enables EcoQoS (Efficiency Mode) for the specified process.
    /// </summary>
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
                StateMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED // Enable EcoQoS
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

    /// <summary>
    /// Checks if the current OS supports EcoQoS (Windows 11 Build 22000+).
    /// </summary>
    public static bool IsEcoQoSSupported()
    {
        var version = Environment.OSVersion.Version;
        // Windows 11 21H2 = 10.0.22000
        return version.Major >= 10 && version.Build >= 22000;
    }
}
