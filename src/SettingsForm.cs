using EfficiencyBooster.Services;

namespace EfficiencyBooster;

/// <summary>
/// Settings dialog for managing keywords and viewing matched processes.
/// </summary>
public class SettingsForm : Form
{
    private readonly SettingsService _settings;
    private readonly ListBox _keywordsList;
    private readonly TextBox _newKeywordBox;
    private readonly Button _addButton;
    private readonly Button _removeButton;
    private readonly ListBox _previewList;
    private readonly Label _previewLabel;

    public SettingsForm(SettingsService settings)
    {
        _settings = settings;

        // Form setup
        Text = "Efficiency Booster - Settings";
        Size = new Size(500, 450);
        MinimumSize = new Size(400, 350);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;

        // Keywords group
        var keywordsGroup = new GroupBox
        {
            Text = "Keywords (process name patterns)",
            Location = new Point(12, 12),
            Size = new Size(460, 180),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        _keywordsList = new ListBox
        {
            Location = new Point(10, 25),
            Size = new Size(320, 110),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };
        _keywordsList.SelectedIndexChanged += (s, e) => UpdateRemoveButton();

        _removeButton = new Button
        {
            Text = "Remove",
            Location = new Point(340, 25),
            Size = new Size(110, 28),
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            Enabled = false
        };
        _removeButton.Click += RemoveKeyword;

        _newKeywordBox = new TextBox
        {
            Location = new Point(10, 145),
            Size = new Size(220, 25),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right
        };
        _newKeywordBox.KeyDown += (s, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                AddKeyword();
                e.Handled = true;
                e.SuppressKeyPress = true;
            }
        };

        _addButton = new Button
        {
            Text = "Add",
            Location = new Point(240, 143),
            Size = new Size(80, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        _addButton.Click += (s, e) => AddKeyword();

        var previewButton = new Button
        {
            Text = "Preview",
            Location = new Point(340, 143),
            Size = new Size(110, 28),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right
        };
        previewButton.Click += (s, e) => RefreshPreview();

        keywordsGroup.Controls.AddRange(new Control[]
        {
            _keywordsList, _removeButton, _newKeywordBox, _addButton, previewButton
        });

        // Preview group
        var previewGroup = new GroupBox
        {
            Text = "Matching Processes Preview",
            Location = new Point(12, 200),
            Size = new Size(460, 160),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        _previewLabel = new Label
        {
            Text = "Click 'Preview' to see processes matching your keywords",
            Location = new Point(10, 25),
            Size = new Size(440, 20),
            ForeColor = SystemColors.GrayText,
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right
        };

        _previewList = new ListBox
        {
            Location = new Point(10, 50),
            Size = new Size(440, 100),
            Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Bottom
        };

        previewGroup.Controls.AddRange(new Control[] { _previewLabel, _previewList });

        // Buttons
        var okButton = new Button
        {
            Text = "OK",
            Location = new Point(290, 370),
            Size = new Size(85, 30),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.OK
        };

        var cancelButton = new Button
        {
            Text = "Cancel",
            Location = new Point(385, 370),
            Size = new Size(85, 30),
            Anchor = AnchorStyles.Bottom | AnchorStyles.Right,
            DialogResult = DialogResult.Cancel
        };

        // Add controls to form
        Controls.AddRange(new Control[] { keywordsGroup, previewGroup, okButton, cancelButton });

        AcceptButton = okButton;
        CancelButton = cancelButton;

        // Load current keywords
        RefreshKeywordsList();
    }

    private void RefreshKeywordsList()
    {
        _keywordsList.Items.Clear();
        foreach (var keyword in _settings.Settings.Keywords)
        {
            _keywordsList.Items.Add(keyword);
        }
        UpdateRemoveButton();
    }

    private void UpdateRemoveButton()
    {
        _removeButton.Enabled = _keywordsList.SelectedIndex >= 0;
    }

    private void AddKeyword()
    {
        var keyword = _newKeywordBox.Text.Trim();
        if (string.IsNullOrEmpty(keyword))
        {
            return;
        }

        if (_settings.AddKeyword(keyword))
        {
            _keywordsList.Items.Add(keyword);
            _newKeywordBox.Clear();
            _newKeywordBox.Focus();

            // Auto-refresh preview
            RefreshPreview();
        }
        else
        {
            MessageBox.Show(
                $"Keyword '{keyword}' already exists.",
                "Duplicate Keyword",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }

    private void RemoveKeyword(object? sender, EventArgs e)
    {
        if (_keywordsList.SelectedItem is string keyword)
        {
            _settings.RemoveKeyword(keyword);
            _keywordsList.Items.Remove(keyword);
            RefreshPreview();
        }
    }

    private void RefreshPreview()
    {
        _previewList.Items.Clear();

        var keywords = _settings.Settings.Keywords;
        if (keywords.Count == 0)
        {
            _previewLabel.Text = "No keywords configured";
            _previewLabel.ForeColor = SystemColors.GrayText;
            return;
        }

        var matches = ProcessMatcher.FindMatchingProcesses(keywords);
        var groups = ProcessMatcher.GroupProcesses(matches);

        if (groups.Count == 0)
        {
            _previewLabel.Text = "No matching processes found";
            _previewLabel.ForeColor = SystemColors.GrayText;
            return;
        }

        _previewLabel.Text = $"Found {matches.Count} processes in {groups.Count} groups:";
        _previewLabel.ForeColor = SystemColors.ControlText;

        foreach (var group in groups)
        {
            var suffix = group.TotalCount > 1 ? $" (+{group.TotalCount - 1} more)" : "";
            _previewList.Items.Add($"{group.ProcessName}{suffix} - {group.DisplayInfo}");
        }
    }
}
