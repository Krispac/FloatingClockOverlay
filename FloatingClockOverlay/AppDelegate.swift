import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var clockWindowController:    ClockWindowController?
    private var mirrorControllers:        [String: ClockWindowController] = [:]
    private var settingsWindowController: SettingsWindowController?
    private var statusItem:               NSStatusItem?
    private var globalMonitor:            Any?
    private var mirrorCancellable:        Any?

    // Set to true only by the explicit "Quit" menu action.
    // Every other termination path is blocked.
    private var allowQuit = false

    // Dynamic menu items refreshed in menuWillOpen
    private var showHideItem:      NSMenuItem?
    private var clickThroughItem:  NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var clockModeItem:     NSMenuItem?
    private var timerModeItem:     NSMenuItem?
    private var stopwatchModeItem: NSMenuItem?
    private var verticalLayoutItem: NSMenuItem?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = YES in Info.plist makes this an accessory (menu-bar-only) app.
        // We still call this defensively in case the policy ever needs adjusting.
        NSApp.setActivationPolicy(.accessory)

        clockWindowController = ClockWindowController()
        setupStatusBar()
        setupGlobalKeyboardShortcut()
        setupMirrorObserver()
        if !ForkConfig.disablesUpstreamServices {
            InstallTracker.trackFirstLaunchIfNeeded()
            UpdateChecker.startAutomaticChecks()
        }
        if ClockSettings.shared.adaptiveColor {
            ScreenSampler.requestPermissionIfNeeded()
        }

        // Allow the Settings quit button to trigger a real quit via notification.
        NotificationCenter.default.addObserver(
            self, selector: #selector(quitApp),
            name: .quitApp, object: nil
        )

        // Double-click on overlay opens Settings.
        NotificationCenter.default.addObserver(
            self, selector: #selector(openSettings),
            name: .openSettings, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        clockWindowController?.savePosition()
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
    }

    // ── Gate: only allow termination when allowQuit is true ──────────────────
    // This blocks accidental ⌘Q or any programmatic terminate unless it came
    // from our explicit quitApp() action.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return allowQuit || isSystemQuit() ? .terminateNow : .terminateCancel
    }

    // Quits that must always work: log out / restart / shut down, and System Settings'
    // "Quit & Reopen" after granting Screen Recording (blocking it made the grant
    // look broken until the user restarted the app by hand).
    private func isSystemQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEQuitApplication else { return false }
        if let reason = event.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue,
           [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog,
            kAERestart, kAEShutDown].map({ OSType($0) }).contains(reason) {
            return true
        }
        if let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value,
           let sender = NSRunningApplication(processIdentifier: pid_t(pid))?.bundleIdentifier,
           sender == "com.apple.systempreferences" || sender == "com.apple.Settings" {
            return true
        }
        return false
    }

    // Closing the last window (e.g. Settings) must never quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Quit (the only real exit path)

    @objc private func quitApp() {
        clockWindowController?.savePosition()
        removeMirrorWindows()
        allowQuit = true
        NSApp.terminate(nil)
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "clock.fill",
            accessibilityDescription: "Floating Clock Overlay"
        )

        let menu = NSMenu()
        menu.delegate = self

        // Keep this short: only the actions used day to day. Everything else
        // lives in Settings.
        let show = NSMenuItem(title: NSLocalizedString("Show Overlay", comment: ""),
                              action: #selector(toggleVisibility), keyEquivalent: "h")
        show.keyEquivalentModifierMask = [.command, .shift]
        let ct   = NSMenuItem(title: NSLocalizedString("Click-Through: ON ✓", comment: ""),
                              action: #selector(toggleClickThrough), keyEquivalent: "")
        ct.keyEquivalentModifierMask = [.command, .option]
        ct.keyEquivalent = "c"
        showHideItem = show; clickThroughItem = ct
        menu.addItem(show)
        menu.addItem(ct)
        menu.addItem(.separator())

        let standard = NSMenuItem(title: NSLocalizedString("Standard Layout", comment: ""),
                                  action: #selector(restoreStandardLayout), keyEquivalent: "")
        standard.target = self
        menu.addItem(standard)

        let vertical = NSMenuItem(title: NSLocalizedString("Vertical Layout", comment: ""),
                                  action: #selector(toggleVerticalLayout), keyEquivalent: "")
        vertical.target = self
        verticalLayoutItem = vertical
        menu.addItem(vertical)

        let modeItem = NSMenuItem(title: NSLocalizedString("Mode", comment: ""), action: nil, keyEquivalent: "")
        modeItem.submenu = buildModeMenu()
        menu.addItem(modeItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: NSLocalizedString("Open Settings", comment: ""),
                                action: #selector(openSettings), keyEquivalent: ","))

        let loginItem = NSMenuItem(title: NSLocalizedString("Launch at Login", comment: ""),
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // ── The ONLY real quit path ───────────────────────────────────────
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Floating Clock Overlay", comment: ""),
                                action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Submenus

    private func buildModeMenu() -> NSMenu {
        let m = NSMenu()
        let ci = NSMenuItem(title: NSLocalizedString("Clock", comment: ""),     action: #selector(setModeClock),     keyEquivalent: "")
        let ti = NSMenuItem(title: NSLocalizedString("Timer", comment: ""),     action: #selector(setModeTimer),     keyEquivalent: "")
        let si = NSMenuItem(title: NSLocalizedString("Stopwatch", comment: ""), action: #selector(setModeStopwatch), keyEquivalent: "")
        clockModeItem = ci; timerModeItem = ti; stopwatchModeItem = si
        m.addItem(ci); m.addItem(ti); m.addItem(si)
        return m
    }

    // MARK: - menuWillOpen — refresh all dynamic labels/states

    func menuWillOpen(_ menu: NSMenu) {
        let s  = ClockSettings.shared
        let tc = TimeController.shared

        let overlayShown = s.isVisible && s.visiblePaneCount > 0
        showHideItem?.title      = overlayShown     ? NSLocalizedString("Hide Overlay", comment: "") : NSLocalizedString("Show Overlay", comment: "")
        clickThroughItem?.title  = s.isClickThrough ? NSLocalizedString("Click-Through: ON ✓", comment: "") : NSLocalizedString("Click-Through: OFF", comment: "")
        launchAtLoginItem?.state = s.launchAtLogin  ? .on                   : .off

        clockModeItem?.state     = s.overlayMode == .clock     ? .on : .off
        timerModeItem?.state     = s.overlayMode == .timer     ? .on : .off
        stopwatchModeItem?.state = s.overlayMode == .stopwatch ? .on : .off
        verticalLayoutItem?.state = s.verticalLayout ? .on : .off
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    @objc private func toggleVisibility() {
        let s = ClockSettings.shared
        if s.visiblePaneCount == 0 {
            // Nothing to show: bring the standard three panes back instead of
            // a single lonely pane.
            restoreStandardLayout()
        } else {
            s.isVisible.toggle()
        }
    }
    @objc private func toggleClickThrough()  { ClockSettings.shared.isClickThrough.toggle() }

    // Returns to the three-pane horizontal layout the user actually uses.
    @objc private func restoreStandardLayout() {
        let s = ClockSettings.shared
        // In clock mode the side clock pane is suppressed, which would leave
        // only two panes. The standard layout means work | timer | clock.
        if s.overlayMode == .clock { s.overlayMode = .timer }
        s.verticalLayout      = false
        s.showWorkTimePane    = true
        s.showPrimaryPane     = true
        s.showClockCompanion  = true
        s.isVisible           = true
    }

    @objc private func toggleVerticalLayout() {
        ClockSettings.shared.verticalLayout.toggle()
    }
    @objc private func toggleLaunchAtLogin() {
        let s = ClockSettings.shared
        s.launchAtLogin = !s.launchAtLogin
        s.applyLaunchAtLogin(s.launchAtLogin)
    }

    @objc private func setModeClock()     { selectMode(.clock) }
    @objc private func setModeTimer()     { selectMode(.timer) }
    @objc private func setModeStopwatch() { selectMode(.stopwatch) }

    private func selectMode(_ mode: OverlayMode) {
        let s = ClockSettings.shared
        s.overlayMode = mode
        s.showPrimaryPane = true
        s.isVisible = true
    }

    // MARK: - Mirror to All Displays

    private func setupMirrorObserver() {
        let s = ClockSettings.shared
        mirrorCancellable = s.$mirrorToAllDisplays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.createMirrorWindows()
                } else {
                    self?.removeMirrorWindows()
                }
            }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func screensChanged() {
        if ClockSettings.shared.mirrorToAllDisplays {
            createMirrorWindows()
        }
    }

    private func createMirrorWindows() {
        removeMirrorWindows()
        guard let mainWindow = clockWindowController?.window else { return }
        let mainScreen = mainWindow.screen ?? NSScreen.main

        for screen in NSScreen.screens {
            if screen == mainScreen { continue }
            let name = screen.localizedName
            let controller = ClockWindowController(restoresSavedPosition: false)

            // Position the mirror at the saved offset for this screen, or center-top
            let d = UserDefaults.standard
            let key = "mirror_\(name)"
            let ox = d.double(forKey: "\(key)_offsetX")
            let oy = d.double(forKey: "\(key)_offsetY")
            if ox != 0 || oy != 0 {
                let origin = NSPoint(x: screen.frame.origin.x + ox,
                                     y: screen.frame.origin.y + oy)
                controller.window?.setFrameOrigin(origin)
            } else {
                let sf = screen.visibleFrame
                let wf = controller.window?.frame ?? .zero
                let origin = NSPoint(x: sf.midX - wf.width / 2,
                                     y: sf.maxY - wf.height - 20)
                controller.window?.setFrameOrigin(origin)
            }

            controller.window?.orderFrontRegardless()
            mirrorControllers[name] = controller
        }
    }

    private func removeMirrorWindows() {
        // Save positions before removing
        for (name, controller) in mirrorControllers {
            if let origin = controller.window?.frame.origin,
               let screen = controller.window?.screen {
                let key = "mirror_\(name)"
                let d = UserDefaults.standard
                d.set(origin.x - screen.frame.origin.x, forKey: "\(key)_offsetX")
                d.set(origin.y - screen.frame.origin.y, forKey: "\(key)_offsetY")
            }
            controller.window?.close()
        }
        mirrorControllers.removeAll()
        UserDefaults.standard.synchronize()
    }

    // MARK: - Global Keyboard Shortcut — ⌘⌥C (toggle click-through)

    private func setupGlobalKeyboardShortcut() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command, .option] && event.keyCode == 8 { // ⌘⌥C = toggle click-through
                DispatchQueue.main.async { self?.toggleClickThrough() }
            } else if flags == [.command, .option] && event.keyCode == 4 { // ⌘⌥H = show/hide overlay
                DispatchQueue.main.async { self?.toggleVisibility() }
            }
        }
    }
}

