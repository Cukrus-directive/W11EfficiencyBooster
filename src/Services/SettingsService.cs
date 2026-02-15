using System.Diagnostics;
using EfficiencyBooster.Models;
using Microsoft.Win32;

namespace EfficiencyBooster.Services;

public class SettingsService
{
    private const string AppName = "EfficiencyBooster";
    private const string TaskName = "EfficiencyBooster_Elevated";
    private const string RunRegistryKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public string AppDataPath { get; }
    public string SettingsFilePath { get; }
    public string LogsPath { get; }
    public AppSettings Settings { get; private set; }

    public SettingsService()
    {
        AppDataPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            AppName);

        SettingsFilePath = Path.Combine(AppDataPath, "settings.json");
        LogsPath = Path.Combine(AppDataPath, "logs");

        Directory.CreateDirectory(AppDataPath);
        Directory.CreateDirectory(LogsPath);

        Settings = AppSettings.Load(SettingsFilePath);

        // Import keywords from old PowerShell location on first run,
        // or populate with defaults if no keywords exist
        if (Settings.Keywords.Count == 0)
        {
            ImportOldKeywords();

            if (Settings.Keywords.Count == 0)
                PopulateDefaultKeywords();
        }
    }

    private void ImportOldKeywords()
    {
        var oldKeywordsFile = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "EfficiencyMode", "keywords.txt");

        if (!File.Exists(oldKeywordsFile))
            return;

        try
        {
            var lines = File.ReadAllLines(oldKeywordsFile)
                .Select(l => l.Trim())
                .Where(l => !string.IsNullOrEmpty(l))
                .ToList();

            if (lines.Count > 0)
            {
                Settings.Keywords = lines;
                Save();
            }
        }
        catch { }
    }

    private void PopulateDefaultKeywords()
    {
        Settings.Keywords = new List<string>
        {
            "asus",
            "copilot",
            "search",
            "steam",
            "powertoys",
            "xbox",
            "SearchIndexer",
            "CompatTelRunner",
            "YourPhone",
            "GameBar"
        };
        Save();
    }

    public void Save() => Settings.Save(SettingsFilePath);

    public bool StartWithWindows
    {
        get
        {
            if (RunAsAdmin)
                return ScheduledTaskExists();

            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, false);
                return !string.IsNullOrEmpty(key?.GetValue(AppName) as string);
            }
            catch { return false; }
        }
        set
        {
            if (RunAsAdmin)
            {
                // When in admin mode, StartWithWindows controls the scheduled task
                if (value)
                    CreateScheduledTask();
                else
                    DeleteScheduledTask();
            }
            else
            {
                try
                {
                    using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
                    if (value)
                        key?.SetValue(AppName, $"\"{Application.ExecutablePath}\"");
                    else
                        key?.DeleteValue(AppName, false);
                }
                catch { }
            }

            Settings.StartWithWindows = value;
            Save();
        }
    }

    public bool RunAsAdmin
    {
        get => Settings.RunAsAdmin;
        set
        {
            if (value)
            {
                // Create elevated scheduled task (triggers UAC prompt)
                if (!CreateScheduledTask())
                    return;

                // Remove registry startup entry — scheduled task replaces it
                try
                {
                    using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
                    key?.DeleteValue(AppName, false);
                }
                catch { }
            }
            else
            {
                // Remove the scheduled task
                DeleteScheduledTask();

                // Restore registry startup entry if StartWithWindows is on
                if (Settings.StartWithWindows)
                {
                    try
                    {
                        using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, true);
                        key?.SetValue(AppName, $"\"{Application.ExecutablePath}\"");
                    }
                    catch { }
                }
            }

            Settings.RunAsAdmin = value;
            Save();
        }
    }

    public static bool IsRunningElevated()
    {
        using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        var principal = new System.Security.Principal.WindowsPrincipal(identity);
        return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
    }

    private bool ScheduledTaskExists()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/Query /TN \"{TaskName}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using var proc = Process.Start(psi);
            proc?.WaitForExit(5000);
            return proc?.ExitCode == 0;
        }
        catch { return false; }
    }

    private bool CreateScheduledTask()
    {
        try
        {
            var exePath = Application.ExecutablePath;
            var args = $"/Create /TN \"{TaskName}\" /TR \"\\\"{exePath}\\\"\" /SC ONLOGON /RL HIGHEST /F";

            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = args,
                UseShellExecute = true,
                Verb = "runas",
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            proc?.WaitForExit(15000);
            return proc?.ExitCode == 0;
        }
        catch
        {
            // User declined UAC or schtasks failed
            return false;
        }
    }

    private void DeleteScheduledTask()
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "schtasks.exe",
                Arguments = $"/Delete /TN \"{TaskName}\" /F",
                UseShellExecute = true,
                Verb = "runas",
                CreateNoWindow = true
            };
            using var proc = Process.Start(psi);
            proc?.WaitForExit(15000);
        }
        catch { }
    }

    public bool AddKeyword(string keyword)
    {
        keyword = keyword.Trim();
        if (string.IsNullOrEmpty(keyword))
            return false;

        if (Settings.Keywords.Any(k => k.Equals(keyword, StringComparison.OrdinalIgnoreCase)))
            return false;

        Settings.Keywords.Add(keyword);
        Save();
        return true;
    }

    public bool RemoveKeyword(string keyword)
    {
        var existing = Settings.Keywords.FirstOrDefault(
            k => k.Equals(keyword, StringComparison.OrdinalIgnoreCase));

        if (existing == null)
            return false;

        Settings.Keywords.Remove(existing);
        Save();
        return true;
    }

    public void UpdateLastRun(int processCount)
    {
        Settings.LastEnforcementRun = DateTime.Now;
        Settings.LastRunProcessCount = processCount;
        Save();
    }
}
