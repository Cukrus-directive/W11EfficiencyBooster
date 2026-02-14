namespace EfficiencyBooster.Services;

public class LogService
{
    private readonly string _logsPath;
    private readonly int _retentionDays;
    private readonly object _lock = new();

    public LogService(string logsPath, int retentionDays = 7)
    {
        _logsPath = logsPath;
        _retentionDays = retentionDays;
        Directory.CreateDirectory(_logsPath);
    }

    public string CurrentLogFile => Path.Combine(_logsPath, $"EfficiencyBooster-{DateTime.Now:yyyy-MM-dd}.log");

    public void Info(string message) => Log("INFO", message);
    public void Warn(string message) => Log("WARN", message);
    public void Error(string message) => Log("ERROR", message);
    public void Error(string message, Exception ex) => Log("ERROR", $"{message}: {ex.Message}");

    private void Log(string level, string message)
    {
        var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] [{level}] {message}";

        lock (_lock)
        {
            try
            {
                File.AppendAllText(CurrentLogFile, line + Environment.NewLine);
            }
            catch { }
        }
    }

    public void CleanOldLogs()
    {
        try
        {
            var cutoffDate = DateTime.Now.AddDays(-_retentionDays);
            foreach (var file in Directory.GetFiles(_logsPath, "EfficiencyBooster-*.log"))
            {
                if (new FileInfo(file).LastWriteTime < cutoffDate)
                    File.Delete(file);
            }
        }
        catch { }
    }

    /// <summary>
    /// Gets all log files sorted by date (newest first).
    /// </summary>
    public string[] GetLogFiles()
    {
        try
        {
            return Directory.GetFiles(_logsPath, "EfficiencyBooster-*.log")
                .OrderByDescending(f => f)
                .ToArray();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }
}
