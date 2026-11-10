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
    private var timerStartItem:    NSMenuItem?
    private var timerResetItem:    NSMenuItem?
    private var swStartItem:       NSMenuItem?
    private var swLapItem:         NSMenuItem?
    private var swResetItem:       NSMenuItem?
    private var themeMenuItem:     NSMenuItem?
    private var sizeMenuItem:      NSMenuItem?
    private var primaryPaneItem:   NSMenuItem?
    private var clockPaneItem:     NSMenuItem?

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

        // ── Primary actions ───────────────────────────────────────────────
        menu.addItem(NSMenuItem(title: NSLocalizedString("Open Settings", comment: ""),
                                action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())

        let show = NSMenuItem(title: NSLocalizedString("Show Overlay", comment: ""),
                              action: #selector(toggleVisibility), keyEquivalent: "")
        let ct   = NSMenuItem(title: NSLocalizedString("Click-Through: ON ✓", comment: ""),
                              action: #selector(toggleClickThrough), keyEquivalent: "")
        showHideItem = show; clickThroughItem = ct
        menu.addItem(show)
        menu.addItem(ct)
        menu.addItem(.separator())

        // ── Launch at Login ───────────────────────────────────────────────
        let loginItem = NSMenuItem(title: NSLocalizedString("Launch at Login", comment: ""),
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // ── Theme submenu ─────────────────────────────────────────────────
        let themeItem = NSMenuItem(title: NSLocalizedString("Theme", comment: ""), action: nil, keyEquivalent: "")
        themeItem.submenu = buildThemeMenu()
        themeMenuItem = themeItem
        menu.addItem(themeItem)

        // ── Size submenu ──────────────────────────────────────────────────
        let sizeItem = NSMenuItem(title: NSLocalizedString("Size", comment: ""), action: nil, keyEquivalent: "")
        sizeItem.submenu = buildSizeMenu()
        sizeMenuItem = sizeItem
        menu.addItem(sizeItem)

        // ── Panels submenu ────────────────────────────────────────────────
        let panelsItem = NSMenuItem(title: NSLocalizedString("Panels", comment: ""), action: nil, keyEquivalent: "")
        panelsItem.submenu = buildPanelsMenu()
        menu.addItem(panelsItem)

        // ── Mode submenu ──────────────────────────────────────────────────
        let modeItem = NSMenuItem(title: NSLocalizedString("Mode", comment: ""), action: nil, keyEquivalent: "")
        modeItem.submenu = buildModeMenu()
        menu.addItem(modeItem)
        menu.addItem(.separator())

        // ── Timer quick controls ──────────────────────────────────────────
        let tStart = NSMenuItem(title: NSLocalizedString("Timer: Start", comment: ""), action: #selector(timerStartPause), keyEquivalent: "")
        let tReset = NSMenuItem(title: NSLocalizedString("Timer: Reset", comment: ""), action: #selector(timerReset),      keyEquivalent: "")
        timerStartItem = tStart; timerResetItem = tReset
        menu.addItem(tStart); menu.addItem(tReset)
        menu.addItem(.separator())

        // ── Stopwatch quick controls ──────────────────────────────────────
        let swStart = NSMenuItem(title: NSLocalizedString("Stopwatch: Start", comment: ""), action: #selector(swStartPause), keyEquivalent: "")
        let swLap   = NSMenuItem(title: NSLocalizedString("Stopwatch: Lap", comment: ""),   action: #selector(swLap),        keyEquivalent: "")
        let swReset = NSMenuItem(title: NSLocalizedString("Stopwatch: Reset", comment: ""), action: #selector(swReset),      keyEquivalent: "")
        swStartItem = swStart; swLapItem = swLap; swResetItem = swReset
        menu.addItem(swStart); menu.addItem(swLap); menu.addItem(swReset)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: NSLocalizedString("Reset Position", comment: ""),
                                action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())

        // ── The ONLY real quit path ───────────────────────────────────────
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Floating Clock Overlay", comment: ""),
                                action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    // MARK: - Submenus

    private func buildThemeMenu() -> NSMenu {
        let m = NSMenu()
        for theme in ClockTheme.allCases {
            let item = NSMenuItem(title: theme.label, action: #selector(setTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.rawValue
            item.target = self
            m.addItem(item)
        }
        return m
    }

    private func buildSizeMenu() -> NSMenu {
        let m = NSMenu()
        for preset in SizePreset.allCases {
            let item = NSMenuItem(title: preset.label, action: #selector(setSize(_:)), keyEquivalent: "")
            item.representedObject = preset.rawValue
            item.target = self
            m.addItem(item)
        }
        return m
    }

    private func buildPanelsMenu() -> NSMenu {
        let m = NSMenu()
        let primary = NSMenuItem(title: NSLocalizedString("Timer Pane", comment: ""),
                                 action: #selector(togglePrimaryPane), keyEquivalent: "")
        let clock = NSMenuItem(title: NSLocalizedString("Side Clock Pane", comment: ""),
                               action: #selector(toggleClockPane), keyEquivalent: "")
        primary.target = self
        clock.target = self
        primaryPaneItem = primary
        clockPaneItem = clock
        m.addItem(primary)
        m.addItem(clock)
        return m
    }

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

        primaryPaneItem?.title   = primaryPaneLabel(for: s.overlayMode)
        primaryPaneItem?.state   = s.showPrimaryPane ? .on : .off
        clockPaneItem?.state     = s.isClockCompanionVisible ? .on : .off
        clockPaneItem?.isEnabled = s.overlayMode != .clock

        let inTimer = s.overlayMode == .timer
        timerStartItem?.isEnabled = inTimer
        timerResetItem?.isEnabled = inTimer
        switch tc.timerState {
        case .idle:     timerStartItem?.title = NSLocalizedString("Timer: Start", comment: "")
        case .running:  timerStartItem?.title = NSLocalizedString("Timer: Pause", comment: "")
        case .paused:   timerStartItem?.title = NSLocalizedString("Timer: Resume", comment: "")
        case .finished: timerStartItem?.title = NSLocalizedString("Timer: Start Break", comment: "")
        case .breakRunning: timerStartItem?.title = NSLocalizedString("Break: Pause", comment: "")
        case .breakPaused:  timerStartItem?.title = NSLocalizedString("Break: Resume", comment: "")
        }

        let inSW = s.overlayMode == .stopwatch
        swStartItem?.isEnabled = inSW
        swLapItem?.isEnabled   = inSW && tc.stopwatchState == .running
        swResetItem?.isEnabled = inSW
        switch tc.stopwatchState {
        case .idle:    swStartItem?.title = NSLocalizedString("Stopwatch: Start", comment: "")
        case .running: swStartItem?.title = NSLocalizedString("Stopwatch: Pause", comment: "")
        case .paused:  swStartItem?.title = NSLocalizedString("Stopwatch: Resume", comment: "")
        }

        // Checkmarks for theme and size submenus
        if let sub = themeMenuItem?.submenu {
            for i in sub.items {
                i.state = (i.representedObject as? String) == s.selectedTheme.rawValue ? .on : .off
            }
        }
        if let sub = sizeMenuItem?.submenu {
            for i in sub.items {
                i.state = (i.representedObject as? String) == s.sizePreset.rawValue ? .on : .off
            }
        }
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
            s.showPrimaryPane = true
            s.isVisible = true
        } else {
            s.isVisible.toggle()
        }
    }
    @objc private func toggleClickThrough()  { ClockSettings.shared.isClickThrough.toggle() }
    @objc private func resetPosition() {
        NotificationCenter.default.post(name: .moveToPreset, object: ClockSettings.PositionPreset.reset)
    }
    @objc private func toggleLaunchAtLogin() {
        let s = ClockSettings.shared
        s.launchAtLogin = !s.launchAtLogin
        s.applyLaunchAtLogin(s.launchAtLogin)
    }

    @objc private func setTheme(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let t = ClockTheme(rawValue: raw) {
            ClockSettings.shared.selectedTheme = t
        }
    }
    @objc private func setSize(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let p = SizePreset(rawValue: raw) {
            ClockSettings.shared.sizePreset = p
        }
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

    private func primaryPaneLabel(for mode: OverlayMode) -> String {
        switch mode {
        case .clock:     return NSLocalizedString("Clock Pane", comment: "")
        case .timer:     return NSLocalizedString("Timer Pane", comment: "")
        case .stopwatch: return NSLocalizedString("Stopwatch Pane", comment: "")
        }
    }

    @objc private func togglePrimaryPane() {
        let s = ClockSettings.shared
        s.showPrimaryPane.toggle()
        if s.showPrimaryPane { s.isVisible = true }
    }

    @objc private func toggleClockPane() {
        let s = ClockSettings.shared
        guard s.overlayMode != .clock else { return }
        s.showClockCompanion.toggle()
        if s.showClockCompanion { s.isVisible = true }
    }

    @objc private func timerStartPause() {
        switch TimeController.shared.timerState {
        case .idle, .paused:  TimeController.shared.timerStart()
        case .running:        TimeController.shared.timerPause()
        case .finished:       TimeController.shared.breakStart()
        case .breakRunning:   TimeController.shared.breakPause()
        case .breakPaused:    TimeController.shared.breakResume()
        }
    }
    @objc private func timerReset() { TimeController.shared.timerReset() }

    @objc private func swStartPause() {
        switch TimeController.shared.stopwatchState {
        case .idle, .paused: TimeController.shared.stopwatchStart()
        case .running:       TimeController.shared.stopwatchPause()
        }
    }
    @objc private func swLap()   { TimeController.shared.stopwatchLap() }
    @objc private func swReset() { TimeController.shared.stopwatchReset() }

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
            let controller = ClockWindowController()

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

