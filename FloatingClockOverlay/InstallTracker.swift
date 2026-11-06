import Foundation

enum InstallTracker {
    private static let hasTrackedKey = "InstallTracker.hasTracked"

    static func trackFirstLaunchIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasTrackedKey) else { return }
        UserDefaults.standard.set(true, forKey: hasTrackedKey)

        let installID = getOrCreateInstallID()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var components = URLComponents()
        components.scheme = "https"
        components.host = "floating-clock-overlay-default-rtdb.firebaseio.com"
        components.path = "/installs/\(installID).json"

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "p": "mac",
            "v": version,
            "b": build,
            "os": os,
            "t": ISO8601DateFormatter().string(from: Date())
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request).resume()
    }

    private static func getOrCreateInstallID() -> String {
        let key = "InstallTracker.installID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
