import AppKit
import CryptoKit
import Security
import SwiftUI

// Personal fork configuration. Upstream's release manifest and install tracker
// must not replace or report this build, otherwise fork changes are lost.
enum ForkConfig {
    static let disablesUpstreamServices = true
}

// Reads update.json from the website rather than GitHub's "latest release", so a
// release can be published first and offered to users only when the manifest says so
// (and pulled again by editing the manifest if it turns out bad).
private struct UpdateManifest: Decodable {
    struct Platform: Decodable {
        let version: String
        let url: URL
        let sha256: String
        let notes: String?
    }
    let mac: Platform?
}

enum UpdateChecker {
    static let manifestURL = URL(string: ProcessInfo.processInfo.environment["FCO_UPDATE_MANIFEST"]
        ?? "https://floating-clock-overlay.web.app/update.json")!
    static let autoCheckKey = "updates.autoCheck"
    private static let skippedKey = "updates.skippedVersion"
    private static let lastCheckKey = "updates.lastCheck"
    private static var timer: Timer?
    private static var panel: NSPanel?

    static var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoCheckKey) }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            check(userInitiated: false)
        }
    }

    static func checkForUpdate() { check(userInitiated: true) }

    static func check(userInitiated: Bool) {
        if !userInitiated {
            guard autoCheckEnabled else { return }
            let last = UserDefaults.standard.double(forKey: lastCheckKey)
            guard Date().timeIntervalSince1970 - last > 20 * 3600 else { return }
        }
        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let manifest = data.flatMap { try? JSONDecoder().decode(UpdateManifest.self, from: $0) }
            DispatchQueue.main.async {
                guard let mac = manifest?.mac else {
                    if userInitiated { info(NSLocalizedString("Couldn't check for updates. Please try again later.", comment: "")) }
                    return
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
                let newer = isVersion(mac.version, newerThan: currentVersion)
                let skipped = UserDefaults.standard.string(forKey: skippedKey) == mac.version
                if newer && (userInitiated || !skipped) {
                    showPanel(for: mac)
                } else if userInitiated {
                    info(String(format: NSLocalizedString("You're up to date (v%@).", comment: ""), currentVersion))
                }
            }
        }.resume()
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func info(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Pop-up

    fileprivate static func showPanel(for update: UpdateManifest.Platform) {
        panel?.close()
        let model = UpdateModel(update: update)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: UpdatePanelView(model: model))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - p.frame.width - 16, y: f.maxY - p.frame.height - 16))
        }
        model.close = { p.close() }
        model.skip = {
            UserDefaults.standard.set(update.version, forKey: skippedKey)
            p.close()
        }
        p.orderFrontRegardless()
        panel = p
    }

    // MARK: - Install

    fileprivate static func install(_ update: UpdateManifest.Platform,
                                    progress: @escaping (String) -> Void,
                                    failed: @escaping (String) -> Void) {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: folder) else {
            return failed(NSLocalizedString("Can't update the app in this folder. Please download the new version from the website.", comment: ""))
        }
        progress(NSLocalizedString("Downloading…", comment: ""))
        URLSession.shared.downloadTask(with: update.url) { tmp, _, error in
            guard let tmp, error == nil else {
                return DispatchQueue.main.async { failed(NSLocalizedString("Download failed.", comment: "")) }
            }
            do {
                let staged = try prepare(downloadedDMG: tmp, expectedSHA: update.sha256)
                DispatchQueue.main.async {
                    progress(NSLocalizedString("Restarting…", comment: ""))
                    relaunch(replacingWith: staged)
                }
            } catch {
                DispatchQueue.main.async { failed(error.localizedDescription) }
            }
        }.resume()
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = NSLocalizedString(s, comment: "") }
    }

    // Verify the download, mount it, check the new app is signed by the same identity
    // as this one, and copy it to a staging folder ready to swap in.
    private static func prepare(downloadedDMG: URL, expectedSHA: String) throws -> URL {
        let data = try Data(contentsOf: downloadedDMG)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA.lowercased() else { throw UpdateError("The download is damaged. Please try again.") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("FCOUpdate-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", downloadedDMG.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) else {
            throw UpdateError("Couldn't open the update.")
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let mountedApp = mount.appendingPathComponent("FloatingClockOverlay.app")
        guard FileManager.default.fileExists(atPath: mountedApp.path), isSignedLikeMe(mountedApp) else {
            throw UpdateError("The update isn't signed correctly, so it wasn't installed.")
        }
        let staged = work.appendingPathComponent("FloatingClockOverlay.app")
        guard run("/usr/bin/ditto", [mountedApp.path, staged.path]) else { throw UpdateError("Couldn't prepare the update.") }
        return staged
    }

    private static func isSignedLikeMe(_ app: URL) -> Bool {
        var me: SecCode?
        var myStatic: SecStaticCode?
        var requirement: SecRequirement?
        var other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &myStatic) == errSecSuccess, let myStatic,
              SecCodeCopyDesignatedRequirement(myStatic, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other else { return false }
        return SecStaticCodeCheckValidity(other, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    // A detached shell waits for this process to exit, swaps the bundle and reopens it.
    private static func relaunch(replacingWith staged: URL) {
        let target = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.3; done
        if /usr/bin/ditto "$2" "$1.updating"; then
          rm -rf "$1.previous" && mv "$1" "$1.previous" && mv "$1.updating" "$1" && rm -rf "$1.previous" \
            || { rm -rf "$1"; mv "$1.previous" "$1"; }
          /usr/bin/xattr -dr com.apple.quarantine "$1" 2>/dev/null
        fi
        rm -rf "$1.updating"
        /usr/bin/open "$1"
        rm -rf "$(dirname "$2")"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", target, staged.path]
        try? p.run()
        NotificationCenter.default.post(name: .quitApp, object: nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

private final class UpdateModel: ObservableObject {
    let update: UpdateManifest.Platform
    @Published var status: String?
    @Published var error: String?
    var close: () -> Void = {}
    var skip: () -> Void = {}
    init(update: UpdateManifest.Platform) { self.update = update }
}

private struct UpdatePanelView: View {
    @ObservedObject var model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available").font(.headline)
                    Text(String(format: NSLocalizedString("Version %@ is ready to install.", comment: ""), model.update.version))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let notes = model.update.notes, !notes.isEmpty {
                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if let status = model.status {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption)
                    Spacer()
                } else {
                    Button("Skip This Version") { model.skip() }.buttonStyle(.plain)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Later") { model.close() }
                    Button("Update Now") {
                        model.error = nil
                        UpdateChecker.install(model.update,
                                              progress: { model.status = $0 },
                                              failed: { model.status = nil; model.error = $0 })
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 14)
        .frame(width: 340)
    }
}
