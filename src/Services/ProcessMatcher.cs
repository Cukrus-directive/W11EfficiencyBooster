using System.Diagnostics;

namespace EfficiencyBooster.Services;

public class ProcessMatcher
{
    public class MatchedProcess
    {
        public int ProcessId { get; set; }
        public string ProcessName { get; set; } = "";
        public string? WindowTitle { get; set; }
    }

    public class ProcessGroup
    {
        public string ProcessName { get; set; } = "";
        public string DisplayInfo { get; set; } = "";
        public int TotalCount => Processes.Count;
        public List<MatchedProcess> Processes { get; set; } = new();
    }

    /// <summary>
    /// Finds all processes matching any of the given keywords (case-insensitive substring match).
    /// </summary>
    public static List<MatchedProcess> FindMatchingProcesses(IEnumerable<string> keywords)
    {
        var keywordList = keywords.ToList();
        if (keywordList.Count == 0)
            return new List<MatchedProcess>();

        var matches = new Dictionary<int, MatchedProcess>();

        foreach (var process in Process.GetProcesses())
        {
            try
            {
                var processName = process.ProcessName;

                foreach (var keyword in keywordList)
                {
                    if (processName.Contains(keyword, StringComparison.OrdinalIgnoreCase))
                    {
                        if (!matches.ContainsKey(process.Id))
                        {
                            string? windowTitle = null;
                            try
                            {
                                windowTitle = string.IsNullOrWhiteSpace(process.MainWindowTitle)
                                    ? null
                                    : process.MainWindowTitle;
                            }
                            catch { }

                            matches[process.Id] = new MatchedProcess
                            {
                                ProcessId = process.Id,
                                ProcessName = processName,
                                WindowTitle = windowTitle
                            };
                        }
                        break;
                    }
                }
            }
            catch { }
            finally
            {
                process.Dispose();
            }
        }

        return matches.Values.ToList();
    }

    /// <summary>
    /// Groups matched processes by process name for display.
    /// </summary>
    public static List<ProcessGroup> GroupProcesses(List<MatchedProcess> processes)
    {
        return processes
            .GroupBy(p => p.ProcessName, StringComparer.OrdinalIgnoreCase)
            .Select(g =>
            {
                var withTitle = g.FirstOrDefault(p => !string.IsNullOrEmpty(p.WindowTitle));
                var displayInfo = withTitle?.WindowTitle ?? "(Background process)";

                if (displayInfo.Length > 60)
                    displayInfo = displayInfo[..57] + "...";

                return new ProcessGroup
                {
                    ProcessName = g.Key,
                    DisplayInfo = displayInfo,
                    Processes = g.ToList()
                };
            })
            .OrderBy(g => g.ProcessName)
            .ToList();
    }
}
