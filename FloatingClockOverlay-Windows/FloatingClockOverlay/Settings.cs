using System.IO;
using System.Text.Json;

namespace FloatingClockOverlay;

public class Settings
{
    public double? Left { get; set; }
    public double? Top { get; set; }
    public bool Use24Hour { get; set; }
    public bool ShowSeconds { get; set; } = true;
    public bool ShowDayOfWeek { get; set; }
    public bool AdaptiveColor { get; set; } = true;
    public bool ClickThrough { get; set; }
    public string ClockLanguage { get; set; } = "";
    public bool AutoCheckUpdates { get; set; } = true;
    public string SkippedVersion { get; set; } = "";
    public string InstallId { get; set; } = "";
    public bool InstallTracked { get; set; }

    private static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FloatingClockOverlay");
    private static readonly string FilePath = Path.Combine(Dir, "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch { }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch { }
    }
}
