using System.IO;
using System.Windows;
using Forms = System.Windows.Forms;
using static FloatingClockOverlay.Strings;

namespace FloatingClockOverlay;

public partial class App : System.Windows.Application
{
    internal static readonly (string Code, string Name)[] Languages =
    {
        ("en", "English"), ("es", "Español"), ("ar", "العربية"), ("hi", "हिन्दी"),
        ("bn", "বাংলা"), ("fr", "Français"), ("de", "Deutsch"), ("ja", "日本語"),
        ("zh", "中文"), ("ko", "한국어"), ("pt", "Português"), ("ru", "Русский"),
        ("tr", "Türkçe"), ("it", "Italiano"),
    };

    private static Mutex? _singleInstance;
    private Forms.NotifyIcon? _trayIcon;
    private ClockWindow? _clockWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += (_, ex) =>
        {
            ReportCrash(ex.Exception);
            ex.Handled = true;
            Shutdown(1);
        };
        AppDomain.CurrentDomain.UnhandledException += (_, ex) => ReportCrash(ex.ExceptionObject as Exception);

        try
        {
            Start(e.Args.Contains("--after-update"));
        }
        catch (Exception ex)
        {
            ReportCrash(ex);
            Shutdown(1);
        }
    }

    private static void ReportCrash(Exception? ex)
    {
        var text = ex?.ToString() ?? "Unknown error";
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FloatingClockOverlay");
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "crash.log"), text);
        }
        catch { }
        System.Windows.MessageBox.Show(text, "Floating Clock Overlay crashed", MessageBoxButton.OK, MessageBoxImage.Error);
    }

    private const string OpenSettingsEventName = "FloatingClockOverlay.OpenSettings";

    // One clock at a time. A copy started by the updater waits for the old one to
    // exit; opening the app again while it runs brings up its Settings instead.
    private static bool AcquireSingleInstance(bool afterUpdate)
    {
        _singleInstance = new Mutex(true, "FloatingClockOverlay.SingleInstance", out bool created);
        if (created) return true;
        if (!afterUpdate)
        {
            try { EventWaitHandle.OpenExisting(OpenSettingsEventName).Set(); } catch { }
            return false;
        }
        try { return _singleInstance.WaitOne(TimeSpan.FromSeconds(10)); }
        catch (AbandonedMutexException) { return true; }
    }

    private void ListenForOpenSettings()
    {
        var signal = new EventWaitHandle(false, EventResetMode.AutoReset, OpenSettingsEventName);
        var thread = new Thread(() =>
        {
            while (signal.WaitOne())
                Dispatcher.BeginInvoke(() => { if (_clockWindow != null) SettingsWindow.ShowFor(_clockWindow); });
        }) { IsBackground = true };
        thread.Start();
    }

    private void Start(bool afterUpdate)
    {
        if (!AcquireSingleInstance(afterUpdate))
        {
            Shutdown();
            return;
        }
        ListenForOpenSettings();
        Updater.CleanUpPreviousUpdate();
        _clockWindow = new ClockWindow();
        _clockWindow.Show();
        var s = _clockWindow.Settings;

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            Text = "Floating Clock Overlay"
        };

        var menu = new Forms.ContextMenuStrip();

        var openSettings = new Forms.ToolStripMenuItem(T("Settings…")) { Font = new System.Drawing.Font(menu.Font, System.Drawing.FontStyle.Bold) };
        openSettings.Click += (_, _) => { if (_clockWindow != null) SettingsWindow.ShowFor(_clockWindow); };
        menu.Items.Add(openSettings);
        menu.Items.Add(new Forms.ToolStripSeparator());

        var showHide = new Forms.ToolStripMenuItem(T("Show/Hide"));
        showHide.Click += (_, _) => _clockWindow?.ToggleVisibility();
        menu.Items.Add(showHide);

        var clickThrough = new Forms.ToolStripMenuItem(T("Click-Through (Ctrl+Alt+C)"));
        clickThrough.Click += (_, _) => _clockWindow?.ToggleClickThrough();
        menu.Items.Add(clickThrough);

        menu.Items.Add(new Forms.ToolStripSeparator());

        var use24 = Toggle(T("24-hour"), () => s.Use24Hour, v => s.Use24Hour = v);
        var seconds = Toggle(T("Show Seconds"), () => s.ShowSeconds, v => s.ShowSeconds = v);
        var day = Toggle(T("Show Day of Week"), () => s.ShowDayOfWeek, v => s.ShowDayOfWeek = v);
        var adaptive = Toggle(T("Adaptive Color"), () => s.AdaptiveColor, v => s.AdaptiveColor = v);
        menu.Items.AddRange(new Forms.ToolStripItem[] { use24, seconds, day, adaptive });

        var langMenu = new Forms.ToolStripMenuItem(T("Clock Language"));
        var langItems = new List<Forms.ToolStripMenuItem>();
        foreach (var (code, name) in Languages.Prepend(("", T("System Default"))))
        {
            var item = new Forms.ToolStripMenuItem(name) { Tag = code };
            item.Click += (_, _) =>
            {
                s.ClockLanguage = code;
                s.Save();
                _clockWindow?.UpdateClock();
            };
            langItems.Add(item);
            langMenu.DropDownItems.Add(item);
        }
        menu.Items.Add(langMenu);

        menu.Items.Add(new Forms.ToolStripSeparator());

        var autoUpdate = Toggle(T("Automatically Check for Updates"), () => s.AutoCheckUpdates, v => s.AutoCheckUpdates = v);
        var checkNow = new Forms.ToolStripMenuItem(T("Check for Updates"));
        checkNow.Click += async (_, _) => await Updater.Check(s, userInitiated: true);
        menu.Items.Add(checkNow);
        menu.Items.Add(autoUpdate);

        var reset = new Forms.ToolStripMenuItem(T("Reset Position"));
        reset.Click += (_, _) => _clockWindow?.ResetPosition();
        menu.Items.Add(reset);

        var quit = new Forms.ToolStripMenuItem(T("Quit"));
        quit.Click += (_, _) => Shutdown();
        menu.Items.Add(quit);

        menu.Opening += (_, _) =>
        {
            clickThrough.Checked = s.ClickThrough;
            use24.Checked = s.Use24Hour;
            seconds.Checked = s.ShowSeconds;
            day.Checked = s.ShowDayOfWeek;
            adaptive.Checked = s.AdaptiveColor;
            autoUpdate.Checked = s.AutoCheckUpdates;
            foreach (var li in langItems) li.Checked = (string)li.Tag! == s.ClockLanguage;
        };

        _trayIcon.ContextMenuStrip = menu;
        _trayIcon.DoubleClick += (_, _) => { if (_clockWindow != null) SettingsWindow.ShowFor(_clockWindow); };
        Updater.StartAutomaticChecks(s);
        InstallTracker.TrackFirstLaunchIfNeeded(s);
    }

    private Forms.ToolStripMenuItem Toggle(string label, Func<bool> get, Action<bool> set)
    {
        var item = new Forms.ToolStripMenuItem(label);
        item.Click += (_, _) =>
        {
            set(!get());
            _clockWindow?.Settings.Save();
            _clockWindow?.UpdateClock();
        };
        return item;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        try { _singleInstance?.ReleaseMutex(); } catch { }
        base.OnExit(e);
    }
}
