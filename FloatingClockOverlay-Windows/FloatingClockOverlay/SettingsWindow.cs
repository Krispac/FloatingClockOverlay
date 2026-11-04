using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using static FloatingClockOverlay.Strings;
using Application = System.Windows.Application;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;
using Color = System.Windows.Media.Color;
using ComboBox = System.Windows.Controls.ComboBox;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Orientation = System.Windows.Controls.Orientation;

namespace FloatingClockOverlay;

public class SettingsWindow : Window
{
    private static SettingsWindow? _open;
    private readonly ClockWindow _clock;
    private Settings S => _clock.Settings;

    public static void ShowFor(ClockWindow clock)
    {
        if (_open != null) { _open.Activate(); return; }
        _open = new SettingsWindow(clock);
        _open.Closed += (_, _) => _open = null;
        _open.Show();
        _open.Activate();
    }

    private SettingsWindow(ClockWindow clock)
    {
        _clock = clock;
        Title = T("Floating Clock Overlay Settings");
        Width = 400;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = new SolidColorBrush(Color.FromRgb(0xF5, 0xF5, 0xF7));
        FontFamily = new FontFamily("Segoe UI");

        var root = new StackPanel { Margin = new Thickness(18) };

        root.Children.Add(Section(T("CLOCK"),
            Check(T("Show Overlay"), () => _clock.IsVisible, v => { if (v != _clock.IsVisible) _clock.ToggleVisibility(); }),
            Check(T("24-hour"), () => S.Use24Hour, v => S.Use24Hour = v),
            Check(T("Show Seconds"), () => S.ShowSeconds, v => S.ShowSeconds = v),
            Check(T("Show Day of Week"), () => S.ShowDayOfWeek, v => S.ShowDayOfWeek = v),
            LanguageRow()));

        root.Children.Add(Section(T("WINDOW"),
            Check(T("Click-Through (Ctrl+Alt+C)"), () => S.ClickThrough, v => { if (v != S.ClickThrough) _clock.ToggleClickThrough(); }),
            Check(T("Adaptive Color"), () => S.AdaptiveColor, v => S.AdaptiveColor = v,
                  T("Switches the text between white and black to match what's behind the clock")),
            ButtonRow(T("Reset Position"), () => _clock.ResetPosition())));

        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "";
        root.Children.Add(Section(T("GENERAL"),
            Check(T("Automatically Check for Updates"), () => S.AutoCheckUpdates, v => S.AutoCheckUpdates = v),
            ButtonRow(T("Check for Updates"), async () => await Updater.Check(S, userInitiated: true)),
            new TextBlock
            {
                Text = $"Floating Clock Overlay v{version}\nCopyright © 2026 Yousa Bin Sadeque. All rights reserved.",
                FontSize = 11, Foreground = Brushes.Gray, Margin = new Thickness(12, 4, 12, 10), TextWrapping = TextWrapping.Wrap
            }));

        var quit = new Button
        {
            Content = T("Quit Floating Clock Overlay"),
            Padding = new Thickness(12, 5, 12, 5),
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 4, 0, 0)
        };
        quit.Click += (_, _) => Application.Current.Shutdown();
        root.Children.Add(quit);

        Content = root;
    }

    private void Changed()
    {
        S.Save();
        _clock.UpdateClock();
    }

    private static Border Section(string title, params UIElement[] rows)
    {
        var panel = new StackPanel();
        panel.Children.Add(new TextBlock
        {
            Text = title, FontSize = 11, FontWeight = FontWeights.SemiBold,
            Foreground = Brushes.Gray, Margin = new Thickness(12, 10, 12, 4)
        });
        foreach (var row in rows) panel.Children.Add(row);
        return new Border
        {
            Background = Brushes.White,
            CornerRadius = new CornerRadius(10),
            BorderBrush = new SolidColorBrush(Color.FromRgb(0xE2, 0xE2, 0xE6)),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 0, 12),
            Padding = new Thickness(0, 0, 0, 6),
            Child = panel
        };
    }

    private UIElement Check(string label, Func<bool> get, Action<bool> set, string? hint = null)
    {
        var box = new CheckBox { IsChecked = get(), Margin = new Thickness(12, 6, 12, 6), VerticalContentAlignment = VerticalAlignment.Center };
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = label, FontSize = 13 });
        if (hint != null)
            text.Children.Add(new TextBlock { Text = hint, FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, MaxWidth = 300 });
        box.Content = text;
        box.Checked += (_, _) => { set(true); Changed(); };
        box.Unchecked += (_, _) => { set(false); Changed(); };
        return box;
    }

    private UIElement LanguageRow()
    {
        var row = new DockPanel { Margin = new Thickness(12, 6, 12, 6) };
        var combo = new ComboBox { Width = 150 };
        foreach (var (code, name) in App.Languages.Prepend(("", T("System Default"))))
        {
            var item = new ComboBoxItem { Content = name, Tag = code };
            combo.Items.Add(item);
            if (code == S.ClockLanguage) combo.SelectedItem = item;
        }
        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedItem is ComboBoxItem { Tag: string code }) { S.ClockLanguage = code; Changed(); }
        };
        DockPanel.SetDock(combo, Dock.Right);
        row.Children.Add(combo);
        row.Children.Add(new TextBlock { Text = T("Clock Language"), FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
        return row;
    }

    private static UIElement ButtonRow(string label, Action action)
    {
        var b = new Button { Content = label, Padding = new Thickness(10, 4, 10, 4), Margin = new Thickness(12, 6, 12, 6), HorizontalAlignment = HorizontalAlignment.Left };
        b.Click += (_, _) => action();
        return b;
    }
}
