using System.Diagnostics;

namespace EfficiencyBooster.Services;

public class EnforcementService
{
    private readonly SettingsService _settings;
    private readonly LogService _log;
    private readonly System.Windows.Forms.Timer _timer;
    private bool _isRunning;

    public event EventHandler<EnforcementResult>? EnforcementCompleted;

    public class EnforcementResult
    {
        public int MatchedCount { get; set; }
        public int SuccessCount { get; set; }
        public int FailCount { get; set; }
        public List<string> ProcessNames { get; set; } = new();
    }

    public EnforcementService(SettingsService settings, LogService log)
    {
        _settings = settings;
        _log = log;

        _timer = new System.Windows.Forms.Timer
        {
            Interval = _settings.Settings.IntervalMinutes * 60 * 1000
        };
        _timer.Tick += (s, e) => RunEnforcement();
    }

    public bool IsRunning => _isRunning;

    public void Start()
    {
        if (_isRunning) return;

        _log.Info("Enforcement service started");
        _log.CleanOldLogs();

        _timer.Interval = _settings.Settings.IntervalMinutes * 60 * 1000;
        _timer.Start();
        _isRunning = true;

        RunEnforcement();
    }

    public void Stop()
    {
        if (!_isRunning) return;

        _timer.Stop();
        _isRunning = false;
        _log.Info("Enforcement service stopped");
    }

    public EnforcementResult RunEnforcement()
    {
        var result = new EnforcementResult();

        try
        {
            _log.Info("========== Enforcement Run Started ==========");

            var keywords = _settings.Settings.Keywords;
            if (keywords.Count == 0)
            {
                _log.Info("No keywords configured. Skipping.");
                _log.Info("========== Enforcement Run Complete ==========");
                return result;
            }

            _log.Info($"Loaded {keywords.Count} keywords: {string.Join(", ", keywords)}");

            var matches = ProcessMatcher.FindMatchingProcesses(keywords);
            result.MatchedCount = matches.Count;

            if (matches.Count == 0)
            {
                _log.Info("No matching processes found.");
                _log.Info("========== Enforcement Run Complete ==========");
                return result;
            }

            _log.Info($"Found {matches.Count} matching processes");

            foreach (var proc in matches)
            {
                bool success = ApplyEfficiencyMode(proc.ProcessId, proc.ProcessName);

                if (success)
                {
                    result.SuccessCount++;
                    result.ProcessNames.Add(proc.ProcessName);
                    _log.Info($"Applied: {proc.ProcessName} (PID: {proc.ProcessId})");
                }
                else
                {
                    result.FailCount++;
                    _log.Warn($"Failed: {proc.ProcessName} (PID: {proc.ProcessId})");
                }
            }

            _log.Info($"Results: {result.SuccessCount} applied, {result.FailCount} failed");
            _log.Info("========== Enforcement Run Complete ==========");

            _settings.UpdateLastRun(result.SuccessCount);
        }
        catch (Exception ex)
        {
            _log.Error("Enforcement run failed", ex);
        }

        EnforcementCompleted?.Invoke(this, result);
        return result;
    }

    private bool ApplyEfficiencyMode(int processId, string processName)
    {
        bool prioritySuccess = false;

        try
        {
            using var process = Process.GetProcessById(processId);
            process.PriorityClass = ProcessPriorityClass.Idle;
            prioritySuccess = true;
        }
        catch { }

        // EcoQoS is bonus - priority is what matters
        EcoQosService.EnableEcoQoS(processId, out _);

        return prioritySuccess;
    }

    public string GetStatusMessage()
    {
        if (!_settings.Settings.EnforcementEnabled)
            return "Paused";

        var lastRun = _settings.Settings.LastEnforcementRun;
        var lastCount = _settings.Settings.LastRunProcessCount;

        if (!lastRun.HasValue)
            return "Running";

        var ago = DateTime.Now - lastRun.Value;
        string agoText;

        if (ago.TotalMinutes < 1)
            agoText = "just now";
        else if (ago.TotalMinutes < 60)
            agoText = $"{(int)ago.TotalMinutes}m ago";
        else if (ago.TotalHours < 24)
            agoText = $"{(int)ago.TotalHours}h ago";
        else
            agoText = $"{(int)ago.TotalDays}d ago";

        return $"Running ({lastCount} processes throttled {agoText})";
    }

    public void UpdateInterval()
    {
        _timer.Interval = _settings.Settings.IntervalMinutes * 60 * 1000;
    }
}
