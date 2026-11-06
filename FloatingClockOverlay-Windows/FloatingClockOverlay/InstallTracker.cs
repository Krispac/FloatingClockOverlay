using System.Net.Http;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace FloatingClockOverlay;

// Anonymous one-time "this copy was opened" ping, same as the Mac app: a random ID,
// the app version, the OS version and a timestamp. Nothing else is sent.
public static class InstallTracker
{
    public static async void TrackFirstLaunchIfNeeded(Settings settings)
    {
        if (settings.InstallTracked || Environment.GetEnvironmentVariable("FCO_NO_TRACKING") == "1") return;
        if (string.IsNullOrEmpty(settings.InstallId))
        {
            settings.InstallId = Guid.NewGuid().ToString().ToUpperInvariant();
            settings.Save();
        }
        try
        {
            var payload = JsonSerializer.Serialize(new
            {
                p = "windows",
                v = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "unknown",
                os = Environment.OSVersion.VersionString,
                t = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ"),
            });
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            var url = $"https://floating-clock-overlay-default-rtdb.firebaseio.com/installs/{settings.InstallId}.json";
            var response = await http.PutAsync(url, new StringContent(payload, Encoding.UTF8, "application/json"));
            if (response.IsSuccessStatusCode)
            {
                settings.InstallTracked = true;
                settings.Save();
            }
        }
        catch { }
    }
}
