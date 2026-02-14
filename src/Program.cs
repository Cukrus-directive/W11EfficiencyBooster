using EfficiencyBooster.Services;

namespace EfficiencyBooster;

static class Program
{
    /// <summary>
    /// The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        // Single instance check
        bool createdNew;
        using var mutex = new Mutex(true, "EfficiencyBooster_SingleInstance", out createdNew);

        if (!createdNew)
        {
            // Another instance is already running
            MessageBox.Show(
                "Efficiency Booster is already running.\n\nCheck the system tray for the icon.",
                "Efficiency Booster",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        // Check OS version
        if (!EcoQosService.IsEcoQoSSupported())
        {
            MessageBox.Show(
                "This application requires Windows 11 21H2 (Build 22000) or later.\n\n" +
                $"Current OS: {Environment.OSVersion.VersionString}",
                "Efficiency Booster - Unsupported OS",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        // Enable visual styles
        ApplicationConfiguration.Initialize();

        // Run the tray application
        Application.Run(new MainForm());
    }
}
