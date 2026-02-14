using System.Text.Json;

namespace EfficiencyBooster.Models;

public class AppSettings
{
    public List<string> Keywords { get; set; } = new();
    public bool StartWithWindows { get; set; } = false;
    public int IntervalMinutes { get; set; } = 60;
    public int LogRetentionDays { get; set; } = 7;
    public DateTime? LastEnforcementRun { get; set; }
    public int LastRunProcessCount { get; set; }
    public bool EnforcementEnabled { get; set; } = true;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static AppSettings Load(string filePath)
    {
        if (!File.Exists(filePath))
            return new AppSettings();

        try
        {
            var json = File.ReadAllText(filePath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public void Save(string filePath)
    {
        var directory = Path.GetDirectoryName(filePath);
        if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            Directory.CreateDirectory(directory);

        File.WriteAllText(filePath, JsonSerializer.Serialize(this, JsonOptions));
    }
}
