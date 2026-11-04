using System.Drawing;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;

namespace FloatingClockOverlay;

public partial class ClockWindow : Window
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x20;
    private const int WS_EX_LAYERED = 0x80;
    private const int WM_HOTKEY = 0x0312;
    private const int HOTKEY_ID = 9000;
    private const uint MOD_CONTROL = 0x0002;
    private const uint MOD_ALT = 0x0001;
    private const uint VK_C = 0x43;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    private static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    private static readonly Dictionary<string, char> NativeZero = new()
    {
        ["ar"] = '٠',
        ["hi"] = '०',
        ["bn"] = '০',
        ["fa"] = '۰',
    };

    public Settings Settings { get; }
    private readonly DispatcherTimer _timer;
    private readonly DispatcherTimer _colorTimer;
    private bool _useWhiteText = true;
    private IntPtr _hwnd;

    public ClockWindow()
    {
        InitializeComponent();
        Settings = Settings.Load();

        if (Settings.Left is double l && Settings.Top is double t && IsOnScreen(l, t))
        {
            Left = l;
            Top = t;
        }
        else
        {
            SetDefaultPosition();
        }

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _timer.Tick += (_, _) => UpdateClock();
        _timer.Start();

        _colorTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        _colorTimer.Tick += (_, _) => UpdateAdaptiveColor();
        _colorTimer.Start();

        UpdateClock();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        _hwnd = new WindowInteropHelper(this).Handle;
        HwndSource.FromHwnd(_hwnd)?.AddHook(WndProc);
        RegisterHotKeyWithRetry(5);
        // Hide our own window from screen captures so adaptive color samples what's behind it.
        if (Environment.GetEnvironmentVariable("FCO_ALLOW_CAPTURE") != "1")
            SetWindowDisplayAffinity(_hwnd, WDA_EXCLUDEFROMCAPTURE);
        if (Settings.ClickThrough) ApplyClickThrough();
    }

    private void RegisterHotKeyWithRetry(int attemptsLeft)
    {
        if (RegisterHotKey(_hwnd, HOTKEY_ID, MOD_CONTROL | MOD_ALT, VK_C) || attemptsLeft <= 0) return;
        var retry = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        retry.Tick += (_, _) => { retry.Stop(); RegisterHotKeyWithRetry(attemptsLeft - 1); };
        retry.Start();
    }

    protected override void OnClosed(EventArgs e)
    {
        UnregisterHotKey(_hwnd, HOTKEY_ID);
        base.OnClosed(e);
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
        {
            ToggleClickThrough();
            handled = true;
        }
        return IntPtr.Zero;
    }

    private CultureInfo ClockCulture =>
        string.IsNullOrEmpty(Settings.ClockLanguage)
            ? CultureInfo.CurrentCulture
            : CultureInfo.GetCultureInfo(Settings.ClockLanguage);

    private string Localize(string s)
    {
        if (!NativeZero.TryGetValue(ClockCulture.TwoLetterISOLanguageName, out var zero)) return s;
        var chars = s.ToCharArray();
        for (int i = 0; i < chars.Length; i++)
            if (chars[i] >= '0' && chars[i] <= '9') chars[i] = (char)(zero + (chars[i] - '0'));
        return new string(chars);
    }

    public void UpdateClock()
    {
        var culture = ClockCulture;
        string format = Settings.Use24Hour
            ? (Settings.ShowSeconds ? "HH:mm:ss" : "HH:mm")
            : (Settings.ShowSeconds ? "h:mm:ss tt" : "h:mm tt");
        var now = DateTime.Now;
        ClockText.Text = Localize(now.ToString(format, culture).Trim());
        DayText.Visibility = Settings.ShowDayOfWeek ? Visibility.Visible : Visibility.Collapsed;
        DayText.Text = culture.DateTimeFormat.GetDayName(now.DayOfWeek);
    }

    private void UpdateAdaptiveColor()
    {
        if (!Settings.AdaptiveColor || !IsVisible)
        {
            SetTextBrush(Brushes.White);
            return;
        }

        double brightness = SampleBrightness();
        if (brightness < 0) return;
        if (_useWhiteText && brightness > 0.55) _useWhiteText = false;
        else if (!_useWhiteText && brightness < 0.45) _useWhiteText = true;
        SetTextBrush(_useWhiteText ? Brushes.White : Brushes.Black);
    }

    private void SetTextBrush(System.Windows.Media.Brush brush)
    {
        ClockText.Foreground = brush;
        DayText.Foreground = brush;
    }

    private double SampleBrightness()
    {
        try
        {
            // Ask Windows for the window's on-screen rectangle instead of scaling
            // WPF units by hand, which goes wrong when monitors use different scaling.
            if (!GetWindowRect(_hwnd, out var r)) return -1;
            int x = r.Left, y = r.Top;
            int w = Math.Max(1, r.Right - r.Left);
            int h = Math.Max(1, r.Bottom - r.Top);

            using var bmp = new Bitmap(w, h);
            using (var g = Graphics.FromImage(bmp))
                g.CopyFromScreen(x, y, 0, 0, new System.Drawing.Size(w, h));

            const int grid = 8;
            double total = 0;
            for (int i = 0; i < grid; i++)
            for (int j = 0; j < grid; j++)
            {
                var c = bmp.GetPixel(i * (w - 1) / (grid - 1), j * (h - 1) / (grid - 1));
                total += (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255.0;
            }
            return total / (grid * grid);
        }
        catch
        {
            return -1;
        }
    }

    private static bool IsOnScreen(double left, double top) =>
        left >= SystemParameters.VirtualScreenLeft - 50 &&
        top >= SystemParameters.VirtualScreenTop - 50 &&
        left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 50 &&
        top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 50;

    private void SetDefaultPosition()
    {
        Left = SystemParameters.WorkArea.Width - 320;
        Top = 40;
    }

    public void ResetPosition()
    {
        SetDefaultPosition();
        SavePosition();
    }

    private void SavePosition()
    {
        Settings.Left = Left;
        Settings.Top = Top;
        Settings.Save();
    }

    private void Border_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            SettingsWindow.ShowFor(this);
            return;
        }
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
            SavePosition();
        }
    }

    private void ApplyClickThrough()
    {
        int extendedStyle = GetWindowLong(_hwnd, GWL_EXSTYLE);
        SetWindowLong(_hwnd, GWL_EXSTYLE,
            Settings.ClickThrough
                ? extendedStyle | WS_EX_TRANSPARENT | WS_EX_LAYERED
                : extendedStyle & ~WS_EX_TRANSPARENT);
    }

    public void ToggleClickThrough()
    {
        Settings.ClickThrough = !Settings.ClickThrough;
        ApplyClickThrough();
        Settings.Save();
    }

    public void ToggleVisibility()
    {
        Visibility = Visibility == Visibility.Visible ? Visibility.Hidden : Visibility.Visible;
    }
}
