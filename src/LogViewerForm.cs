using EfficiencyBooster.Services;

namespace EfficiencyBooster;

/// <summary>
/// Log viewer dialog showing recent log entries.
/// </summary>
public class LogViewerForm : Form
{
    private readonly LogService _log;
    private readonly TextBox _logTextBox;
    private readonly ComboBox _fileSelector;

    public LogViewerForm(LogService log)
    {
        _log = log;

        // Form setup
        Text = "Efficiency Booster - Logs";
        Size = new Size(700, 500);
        MinimumSize = new Size(500, 300);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;

        // File selector
        var fileLabel = new Label
        {
            Text = "Log file:",
            Location = new Point(12, 15),
            Size = new Size(60, 20),
            TextAlign = ContentAlignment.MiddleRight
        };

        _fileSelector = new ComboBox
        {
            Location = new Point(75, 12),
            Size = new Size(250, 25),
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Top | AnchorStyles.Left
        };
        _fileSelector.SelectedIndexChanged += (s, e) => LoadSelectedLog();

        var refreshButton = new Button
        {
            Text = "Refresh",
            Location = new Point(335, 10),
            Size = new Size(80, 28),
            Anchor = AnchorStyles.Top | AnchorStyles.Left
        };
        refreshButton.Click += (s, e) => RefreshLogs();

        var openFolderButton = new Button
        {
            Text = "Open Folder",
            Location = new Point(420, 10),
            Size = new Size(100, 28),
            Anchor = AnchorStyles.Top | AnchorStyles.Left
        };
        openFolderButton.Click += (s, e) => OpenLogsFolder();

        // Log text box
        _logTextBox = new TextBox
        {
            Location = new Point(12, 45),
            Size = new Size(660, 360),
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Both,
            Font = new Font("Consolas", 9),
            WordWrap = false,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        // Close button
        var closeButton = new Button
        {
            Text = "Close",
            Location = new Point(590, 420),
            Size = new Size(85, 30),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.OK
        };

        // Add controls
        Controls.AddRange(new Control[]
        {
            fileLabel, _fileSelector, refreshButton, openFolderButton, _logTextBox, closeButton
        });

        AcceptButton = closeButton;

        // Load log files
        RefreshLogs();
    }

    private void RefreshLogs()
    {
        _fileSelector.Items.Clear();

        var files = _log.GetLogFiles();
        foreach (var file in files)
        {
            _fileSelector.Items.Add(Path.GetFileName(file));
        }

        if (_fileSelector.Items.Count > 0)
        {
            _fileSelector.SelectedIndex = 0;
        }
        else
        {
            _logTextBox.Text = "No log files found.";
        }
    }

    private void LoadSelectedLog()
    {
        if (_fileSelector.SelectedItem is not string fileName)
        {
            return;
        }

        var files = _log.GetLogFiles();
        var selectedFile = files.FirstOrDefault(f => Path.GetFileName(f) == fileName);

        if (selectedFile != null && File.Exists(selectedFile))
        {
            try
            {
                // Read with sharing to avoid locking issues
                using var stream = new FileStream(selectedFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                using var reader = new StreamReader(stream);
                _logTextBox.Text = reader.ReadToEnd();

                // Scroll to bottom
                _logTextBox.SelectionStart = _logTextBox.Text.Length;
                _logTextBox.ScrollToCaret();
            }
            catch (Exception ex)
            {
                _logTextBox.Text = $"Error reading log file: {ex.Message}";
            }
        }
    }

    private void OpenLogsFolder()
    {
        try
        {
            var files = _log.GetLogFiles();
            var folder = files.Length > 0
                ? Path.GetDirectoryName(files[0])
                : Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);

            if (!string.IsNullOrEmpty(folder) && Directory.Exists(folder))
            {
                System.Diagnostics.Process.Start("explorer.exe", folder);
            }
        }
        catch
        {
            // Ignore errors opening folder
        }
    }
}
