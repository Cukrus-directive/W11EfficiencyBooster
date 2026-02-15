using EfficiencyBooster.Services;
using System.Reflection;

namespace EfficiencyBooster;

/// <summary>
/// Hidden form hosting the system tray icon. All interaction is through the tray icon.
/// </summary>
public partial class MainForm : Form
{
    private readonly NotifyIcon _trayIcon;
    private readonly ContextMenuStrip _contextMenu;
    private readonly SettingsService _settings;
    private readonly LogService _log;
    private readonly EnforcementService _enforcement;

    private ToolStripMenuItem _statusItem = null!;
    private ToolStripMenuItem _startWithWindowsItem = null!;
    private ToolStripMenuItem _runAsAdminItem = null!;
    private ToolStripMenuItem _enabledItem = null!;

    public MainForm()
    {
        _settings = new SettingsService();
        _log = new LogService(_settings.LogsPath, _settings.Settings.LogRetentionDays);
        _enforcement = new EnforcementService(_settings, _log);
        _enforcement.EnforcementCompleted += OnEnforcementCompleted;

        _contextMenu = CreateContextMenu();

        _trayIcon = new NotifyIcon
        {
            Icon = LoadTrayIcon(),
            Text = "Efficiency Booster",
            ContextMenuStrip = _contextMenu,
            Visible = true
        };
        _trayIcon.DoubleClick += (s, e) => ShowSettingsDialog();

        // Keep form hidden
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        FormBorderStyle = FormBorderStyle.None;
        Opacity = 0;

        if (_settings.Settings.EnforcementEnabled)
            _enforcement.Start();

        UpdateStatusDisplay();
    }

    private Icon LoadTrayIcon()
    {
        try
        {
            var assembly = Assembly.GetExecutingAssembly();
            using var stream = assembly.GetManifestResourceStream("EfficiencyBooster.Resources.tray-icon.ico");
            if (stream != null)
                return new Icon(stream);
        }
        catch { }

        return SystemIcons.Application;
    }

    private ContextMenuStrip CreateContextMenu()
    {
        var menu = new ContextMenuStrip();

        _statusItem = new ToolStripMenuItem("Status: Initializing...") { Enabled = false };
        menu.Items.Add(_statusItem);
        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(new ToolStripMenuItem("Run Now", null, (s, e) => RunNow()));
        menu.Items.Add(new ToolStripMenuItem("Edit Keywords...", null, (s, e) => ShowSettingsDialog()));
        menu.Items.Add(new ToolStripMenuItem("View Logs...", null, (s, e) => ShowLogsDialog()));
        menu.Items.Add(new ToolStripSeparator());

        _enabledItem = new ToolStripMenuItem("Enabled", null, (s, e) => ToggleEnabled())
        {
            Checked = _settings.Settings.EnforcementEnabled,
            CheckOnClick = false
        };
        menu.Items.Add(_enabledItem);

        _startWithWindowsItem = new ToolStripMenuItem("Start with Windows", null, (s, e) => ToggleStartWithWindows())
        {
            Checked = _settings.StartWithWindows,
            CheckOnClick = false
        };
        menu.Items.Add(_startWithWindowsItem);

        _runAsAdminItem = new ToolStripMenuItem("Run as Admin (Full Coverage)", null, (s, e) => ToggleRunAsAdmin())
        {
            Checked = _settings.RunAsAdmin,
            CheckOnClick = false
        };
        menu.Items.Add(_runAsAdminItem);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Exit", null, (s, e) => ExitApplication()));

        return menu;
    }

    private void UpdateStatusDisplay()
    {
        var status = _enforcement.GetStatusMessage();
        _statusItem.Text = $"Status: {status}";
        _trayIcon.Text = $"Efficiency Booster\n{status}";
    }

    private void OnEnforcementCompleted(object? sender, EnforcementService.EnforcementResult result)
    {
        UpdateStatusDisplay();

        if (result.SuccessCount > 0)
        {
            var names = result.ProcessNames.Distinct().Take(3).ToList();
            var moreCount = result.ProcessNames.Distinct().Count() - names.Count;
            var text = string.Join(", ", names);
            if (moreCount > 0)
                text += $" +{moreCount} more";

            _trayIcon.ShowBalloonTip(3000, "Efficiency Mode Applied",
                $"Throttled {result.SuccessCount} processes: {text}", ToolTipIcon.Info);
        }
    }

    private void RunNow()
    {
        _log.Info("Manual enforcement run triggered");
        _enforcement.RunEnforcement();
        UpdateStatusDisplay();
    }

    private void ShowSettingsDialog()
    {
        using var dialog = new SettingsForm(_settings);
        if (dialog.ShowDialog() == DialogResult.OK)
        {
            _enforcement.UpdateInterval();
            UpdateStatusDisplay();
        }
    }

    private void ShowLogsDialog()
    {
        using var dialog = new LogViewerForm(_log);
        dialog.ShowDialog();
    }

    private void ToggleEnabled()
    {
        _settings.Settings.EnforcementEnabled = !_settings.Settings.EnforcementEnabled;
        _settings.Save();
        _enabledItem.Checked = _settings.Settings.EnforcementEnabled;

        if (_settings.Settings.EnforcementEnabled)
        {
            _enforcement.Start();
            _log.Info("Enforcement enabled by user");
        }
        else
        {
            _enforcement.Stop();
            _log.Info("Enforcement disabled by user");
        }

        UpdateStatusDisplay();
    }

    private void ToggleStartWithWindows()
    {
        _settings.StartWithWindows = !_settings.StartWithWindows;
        _startWithWindowsItem.Checked = _settings.StartWithWindows;
        _log.Info($"Start with Windows: {_settings.StartWithWindows}");
    }

    private void ToggleRunAsAdmin()
    {
        var newValue = !_settings.RunAsAdmin;
        _settings.RunAsAdmin = newValue;

        // RunAsAdmin setter returns early (doesn't change value) if UAC was declined
        _runAsAdminItem.Checked = _settings.RunAsAdmin;
        _startWithWindowsItem.Checked = _settings.StartWithWindows;

        if (_settings.RunAsAdmin)
        {
            _log.Info("Run as Admin enabled — scheduled task created");
            if (!SettingsService.IsRunningElevated())
            {
                _trayIcon.ShowBalloonTip(5000, "Admin Mode Enabled",
                    "Takes effect on next login. Restart the app for immediate effect.", ToolTipIcon.Info);
            }
        }
        else
        {
            _log.Info("Run as Admin disabled — scheduled task removed");
        }
    }

    private void ExitApplication()
    {
        _enforcement.Stop();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        Application.Exit();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }

    protected override void SetVisibleCore(bool value)
    {
        if (!IsHandleCreated)
        {
            CreateHandle();
            value = false;
        }
        base.SetVisibleCore(value);
    }
}
