using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using static FloatingClockOverlay.Strings;
using Application = System.Windows.Application;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using MessageBox = System.Windows.MessageBox;
using Orientation = System.Windows.Controls.Orientation;

namespace FloatingClockOverlay;

// Reads update.json from the website, not GitHub's latest release, so a release can be
// published first and offered only when the manifest points at it (or pulled back).
public static class Updater
{
    private static readonly string ManifestUrl =
        Environment.GetEnvironmentVariable("FCO_UPDATE_MANIFEST") ?? "https://floating-clock-overlay.web.app/update.json";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };
    private static System.Windows.Threading.DispatcherTimer? _timer;
    private static Window? _popup;

    private record PlatformInfo(string version, string url, string sha256, string? notes);
    private record Manifest(PlatformInfo? windows);

    public static Version CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0);

    public static void CleanUpPreviousUpdate()
    {
        try
        {
            var old = Environment.ProcessPath + ".old";
            if (File.Exists(old)) File.Delete(old);
        }
        catch { }
    }

    public static void StartAutomaticChecks(Settings settings)
    {
        _timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
        _timer.Tick += async (_, _) =>
        {
            _timer.Interval = TimeSpan.FromHours(6);
            if (settings.AutoCheckUpdates) await Check(settings, userInitiated: false);
        };
        _timer.Start();
    }

    public static async Task Check(Settings settings, bool userInitiated)
    {
        PlatformInfo? win = null;
        try
        {
            var json = await Http.GetStringAsync(ManifestUrl + "?t=" + DateTime.UtcNow.Ticks);
            win = JsonSerializer.Deserialize<Manifest>(json)?.windows;
        }
        catch { }

        if (win == null || !Version.TryParse(win.version, out var latest))
        {
            if (userInitiated) MessageBox.Show(T("Couldn't check for updates. Please try again later."), "Floating Clock Overlay");
            return;
        }

        bool newer = latest > CurrentVersion;
        if (newer && (userInitiated || settings.SkippedVersion != win.version))
            ShowPopup(settings, win);
        else if (userInitiated)
            MessageBox.Show(string.Format(T("You're up to date (v{0})."), CurrentVersion.ToString(3)), "Floating Clock Overlay");
    }

    private static void ShowPopup(Settings settings, PlatformInfo info)
    {
        _popup?.Close();

        var status = new TextBlock { FontSize = 12, Foreground = Brushes.Gray, Margin = new Thickness(0, 6, 0, 0) };
        var skip = new Button { Content = T("Skip This Version"), Padding = new Thickness(8, 3, 8, 3) };
        var later = new Button { Content = T("Later"), Padding = new Thickness(8, 3, 8, 3), Margin = new Thickness(6, 0, 0, 0) };
        var update = new Button { Content = T("Update Now"), Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0), IsDefault = true };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
        buttons.Children.Add(skip);
        buttons.Children.Add(later);
        buttons.Children.Add(update);

        var body = new StackPanel { Margin = new Thickness(16) };
        body.Children.Add(new TextBlock { Text = T("Update available"), FontSize = 15, FontWeight = FontWeights.SemiBold });
        body.Children.Add(new TextBlock { Text = string.Format(T("Version {0} is ready to install."), info.version), FontSize = 12, Foreground = Brushes.Gray });
        if (!string.IsNullOrWhiteSpace(info.notes))
            body.Children.Add(new TextBlock { Text = info.notes, FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0), MaxHeight = 60 });
        body.Children.Add(status);
        body.Children.Add(buttons);

        var work = SystemParameters.WorkArea;
        var win = new Window
        {
            Title = "Floating Clock Overlay",
            Width = 360,
            SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize,
            WindowStyle = WindowStyle.ToolWindow,
            Topmost = true,
            ShowInTaskbar = false,
            Content = body,
        };
        win.Loaded += (_, _) =>
        {
            win.Left = work.Right - win.ActualWidth - 16;
            win.Top = work.Bottom - win.ActualHeight - 16;
        };

        skip.Click += (_, _) => { settings.SkippedVersion = info.version; settings.Save(); win.Close(); };
        later.Click += (_, _) => win.Close();
        update.Click += async (_, _) =>
        {
            buttons.IsEnabled = false;
            status.Foreground = Brushes.Gray;
            status.Text = T("Downloading…");
            try
            {
                await Install(info);
            }
            catch (Exception ex)
            {
                status.Foreground = Brushes.Red;
                status.Text = ex.Message;
                buttons.IsEnabled = true;
            }
        };

        _popup = win;
        win.Show();
    }

    private static async Task Install(PlatformInfo info)
    {
        var current = Environment.ProcessPath ?? throw new Exception(T("Couldn't prepare the update."));
        var dir = Path.GetDirectoryName(current)!;
        var downloaded = Path.Combine(dir, Path.GetFileName(current) + ".new");

        byte[] data;
        try { data = await Http.GetByteArrayAsync(info.url); }
        catch { throw new Exception(T("Download failed.")); }

        var hash = Convert.ToHexString(SHA256.HashData(data)).ToLowerInvariant();
        if (hash != info.sha256.ToLowerInvariant()) throw new Exception(T("The download is damaged. Please try again."));

        try
        {
            await File.WriteAllBytesAsync(downloaded, data);
            // Windows lets a running exe be renamed, so swap files then start the new one.
            var old = current + ".old";
            if (File.Exists(old)) File.Delete(old);
            File.Move(current, old);
            try
            {
                File.Move(downloaded, current);
            }
            catch
            {
                File.Move(old, current);
                throw;
            }
        }
        catch
        {
            try { if (File.Exists(downloaded)) File.Delete(downloaded); } catch { }
            throw new Exception(T("Couldn't prepare the update."));
        }

        Process.Start(new ProcessStartInfo(current, "--after-update") { UseShellExecute = true });
        Application.Current.Shutdown();
    }
}
