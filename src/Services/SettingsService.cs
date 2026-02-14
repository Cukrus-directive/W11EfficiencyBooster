using EfficiencyBooster.Models;
using Microsoft.Win32;

namespace EfficiencyBooster.Services;

public class SettingsService
{
    private const string AppName = "EfficiencyBooster";
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

        // Import keywords from old PowerShell location on first run
        if (Settings.Keywords.Count == 0)
            ImportOldKeywords();
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

    public void Save() => Settings.Save(SettingsFilePath);

    public bool StartWithWindows
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunRegistryKey, false);
                return !string.IsNullOrEmpty(key?.GetValue(AppName) as string);
            }
            catch { return false; }
        }
        set
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

            Settings.StartWithWindows = value;
            Save();
        }
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
