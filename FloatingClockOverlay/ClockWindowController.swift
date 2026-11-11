import AppKit
import SwiftUI
import Combine

class ClockWindowController: NSWindowController, NSWindowDelegate {

    private let s = ClockSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var savedFrameBeforeFullscreen: NSRect?
    private var burnInTimer: Timer?
    private var burnInDirection: Int = 1  // alternates drift direction
    private var dvdTimer: Timer?
    private var timerStateSink: AnyCancellable?
    private var dvdVelocity: CGPoint = CGPoint(x: 0.4, y: 0.3)
    private var dvdPosition: CGPoint = .zero
    private var isDVDBouncing = false
    private var isRestoringPosition = true
    private var pendingSavedScreenRestore = false
    private var positionRestoreTimer: Timer?
    // Set by every programmatic frame change. Cleared only by a real user drag or
    // an explicit save, so a system nudge after wake cannot become the new spot.
    private var ignoreSystemPositionSaves = false
    private var userMoveWorkItem: DispatchWorkItem?
    private var dvdLastTimestamp: TimeInterval = 0
    private var lastVisiblePanes: [OverlayPaneKind] = []
    private var isUpdatingPaneLayout = false
    private var isApplyingProgrammaticFrame = false
    private var transparencyPanel: TransparencyPanel?
    private let restoresSavedPosition: Bool

    init(restoresSavedPosition: Bool = true) {
        self.restoresSavedPosition = restoresSavedPosition
        let window = ClockWindow(
            contentRect: .zero,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
        setupObservers()
        setupAlwaysOnTop()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Initial Setup

    private func configureWindow() {
        guard let window = window else { return }

        window.delegate                    = self
        window.level                       = .screenSaver   // above everything
        window.isOpaque                    = false
        window.backgroundColor             = .clear
        window.hasShadow                   = false
        // canJoinAllSpaces  → visible on every Space
        // fullScreenAuxiliary → visible over full-screen apps
        // stationary        → doesn't move during Spaces animation
        window.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents          = s.isClickThrough
        window.alphaValue                  = s.windowOpacity
        // Sensible drag-resize limits
        window.minSize = NSSize(width: 80,   height: 30)
        window.maxSize = NSSize(width: 3000, height: 1000)

        window.contentView = NSHostingView(rootView: ClockView())
        lastVisiblePanes = s.visiblePaneKinds

        isRestoringPosition = true
        if s.isFullScreen {
            applyFullScreen(true, animate: false)
        } else {
            applyPreset(s.sizePreset, animate: false)
            restorePosition()
        }
        isRestoringPosition = false

        if s.isVisible && s.visiblePaneCount > 0 { window.orderFrontRegardless() }
        setupBurnInPrevention()
        setupDVDBounce()
        setupTransparencyPanel()
        applyWindowOpacity()
    }

    // Monitors left of or below the main display have negative coordinates, so
    // "has a saved position" can't be judged by sign.
    private var hasSavedPosition: Bool { UserDefaults.standard.object(forKey: "windowX") != nil }

    private func restorePosition() {
        guard let window = window else { return }
        if restoreToSavedScreen(window, allowClamp: true) { return }

        if s.windowScreenID != 0 || !s.windowScreenName.isEmpty {
            // The saved external display is not connected yet. Show a
            // temporary fallback, but keep the saved monitor/offset intact.
            restoreFallback(window)
            beginSavedScreenRestore()
        } else {
            restoreFallback(window)
        }
    }

    private func restoreToSavedScreen(_ window: NSWindow, allowClamp: Bool = false) -> Bool {
        guard s.windowScreenID != 0 || !s.windowScreenName.isEmpty,
              let targetScreen = savedScreen()
        else { return false }
        var origin = NSPoint(x: targetScreen.frame.origin.x + s.windowScreenOffsetX,
                             y: targetScreen.frame.origin.y + s.windowScreenOffsetY)
        let targetFrame = NSRect(origin: origin, size: window.frame.size)
        if !targetScreen.visibleFrame.intersects(targetFrame) {
            guard allowClamp else { return false }
            let vf = targetScreen.visibleFrame
            origin.x = min(max(origin.x, vf.minX), max(vf.minX, vf.maxX - targetFrame.width))
            origin.y = min(max(origin.y, vf.minY), max(vf.minY, vf.maxY - targetFrame.height))
        }
        suppressPositionSaves()
        isRestoringPosition = true
        window.setFrameOrigin(origin)
        isRestoringPosition = false
        if s.windowScreenName != targetScreen.localizedName {
            s.windowScreenName = targetScreen.localizedName
        }
        let targetID = Self.displayID(of: targetScreen)
        if targetID != 0, s.windowScreenID != targetID {
            s.windowScreenID = targetID
        }
        PositionLog.write("restored to \(targetScreen.localizedName) origin=\(Int(origin.x)),\(Int(origin.y))")
        return true
    }

    private func restoreFallback(_ window: NSWindow) {
        if hasSavedPosition {
            let frame = NSRect(origin: NSPoint(x: s.windowX, y: s.windowY), size: window.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                isRestoringPosition = true
                window.setFrameOrigin(frame.origin)
                isRestoringPosition = false
                return
            }
        }
        // Temporary spot only: saving it would overwrite the monitor we retry for.
        suppressPositionSaves()
        isRestoringPosition = true
        moveToPreset(.topRight, save: false)
        isRestoringPosition = false
    }

    private func beginSavedScreenRestore() {
        guard s.windowScreenID != 0 || !s.windowScreenName.isEmpty else { return }
        PositionLog.write("waiting for saved screen id=\(s.windowScreenID) name=\"\(s.windowScreenName)\"; connected=\(PositionLog.screenSummary())")
        pendingSavedScreenRestore = true
        positionRestoreTimer?.invalidate()
        let started = Date()
        positionRestoreTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.restoreSavedWindowPositionIfPossible() {
                self.finishSavedScreenRestore()
            } else if Date().timeIntervalSince(started) >= 60 {
                // Keep the saved position pending. A later display-change
                // notification, or a manual move, will resolve it.
                timer.invalidate()
                PositionLog.write("gave up waiting after 60s; connected=\(PositionLog.screenSummary())")
            }
        }
        if restoreSavedWindowPositionIfPossible() {
            finishSavedScreenRestore()
        }
    }

    private func finishSavedScreenRestore() {
        pendingSavedScreenRestore = false
        positionRestoreTimer?.invalidate()
        positionRestoreTimer = nil
    }

    private func cancelPendingSavedScreenRestore() {
        pendingSavedScreenRestore = false
        positionRestoreTimer?.invalidate()
        positionRestoreTimer = nil
    }

    private func suppressPositionSaves() {
        ignoreSystemPositionSaves = true
    }

    private var isPositionSaveSuppressed: Bool {
        ignoreSystemPositionSaves
    }

    // A real drag starts with windowWillMove; keeping that signal (plus the
    // pressed-button check) means a manual move is never mistaken for a
    // system reflow after wake.
    private func noteUserMove() {
        userMoveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.userMoveWorkItem = nil }
        userMoveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    private var isUserMovingWindow: Bool {
        userMoveWorkItem != nil || NSEvent.pressedMouseButtons != 0
    }

    // MARK: - Always On Top (across every app switch)

    private func setupAlwaysOnTop() {
        // Every time the user switches to any app, push the clock back to front.
        // The .screenSaver level already beats normal windows; this call handles
        // edge cases (full-screen games, presentation tools, etc.).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(bringToFront),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        if restoresSavedPosition {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleWillSleep),
                name: NSWorkspace.willSleepNotification,
                object: nil
            )
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleDidWake),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(handleScreensDidWake),
                name: NSWorkspace.screensDidWakeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleScreenParametersChanged),
                name: NSApplication.didChangeScreenParametersNotification,
                object: nil
            )
        }
    }

    @objc private func bringToFront() {
        guard s.isVisible, s.visiblePaneCount > 0 else { return }
        // Small delay so the newly activated app finishes raising its own windows first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // orderFrontRegardless bypasses the normal "active app" restriction.
            self?.window?.orderFrontRegardless()
        }
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        if !pendingSavedScreenRestore { savePosition() }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        restoreAfterDisplayChange()
        // Fallback for wake paths where screensDidWake is delayed or absent.
        // The display check keeps a DarkWake from starting the work session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ClockSettings.shared.refreshWorkSessionStartIfNeeded(requireAwakeDisplay: true)
        }
    }

    // A full display wake is the point where the user can actually start
    // working. DarkWake does not post this notification, so maintenance wakes
    // cannot move the work-time start earlier.
    @objc private func handleScreensDidWake(_ notification: Notification) {
        ClockSettings.shared.refreshWorkSessionStartIfNeeded()
        restoreAfterDisplayChange()
    }

    @objc private func handleScreenParametersChanged(_ notification: Notification) {
        restoreAfterDisplayChange()
    }

    // macOS can reflow borderless windows when displays go to sleep or the
    // monitor layout changes. Reapply the last user position after the display
    // stack has settled, using the saved screen-relative coordinates.
    private func restoreAfterDisplayChange() {
        guard restoresSavedPosition else { return }
        PositionLog.write("display change; connected=\(PositionLog.screenSummary())")
        if s.windowScreenID != 0 || !s.windowScreenName.isEmpty {
            beginSavedScreenRestore()
        } else {
            _ = restoreSavedWindowPositionIfPossible()
        }
    }

    @discardableResult
    private func restoreSavedWindowPositionIfPossible() -> Bool {
        guard let window = window, !s.isFullScreen else { return true }
        if restoreToSavedScreen(window, allowClamp: true) { return true }

        // Wait for a saved external display instead of overwriting its
        // position with the screen that macOS temporarily reflowed us onto.
        guard s.windowScreenID == 0 && s.windowScreenName.isEmpty else { return false }

        let savedFrame = NSRect(
            origin: NSPoint(x: s.windowX, y: s.windowY),
            size: window.frame.size
        )
        if hasSavedPosition,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) {
            suppressPositionSaves()
            isRestoringPosition = true
            window.setFrameOrigin(savedFrame.origin)
            isRestoringPosition = false
            return true
        }

        suppressPositionSaves()
        isRestoringPosition = true
        clampToScreen(window)
        isRestoringPosition = false
        return true
    }

    // MARK: - Observers

    private func setupObservers() {
        NotificationCenter.default
            .publisher(for: .userDragBegan)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isDVDBouncing else { return }
                self.ignoreSystemPositionSaves = false
                self.noteUserMove()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .switchScreen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.moveToNextScreen() }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .userInteraction)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ignoreSystemPositionSaves = false }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .toggleTransparency)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.s.quickDimmed.toggle() }
            .store(in: &cancellables)

        s.$isClickThrough
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ct in
                // .resizable stays in the mask always — mouse events are what
                // control whether the user can interact (drag/resize).
                self?.applyMousePassthrough()
            }
            .store(in: &cancellables)

        timerStateSink = TimeController.shared.$timerState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyMousePassthrough() }

        s.$windowOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyWindowOpacity() }
            .store(in: &cancellables)

        s.$quickDimmed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyWindowOpacity() }
            .store(in: &cancellables)

        s.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self = self else { return }
                if visible && self.s.visiblePaneCount > 0 {
                    self.window?.orderFrontRegardless()
                } else {
                    self.window?.orderOut(nil)
                }
                self.updateTransparencyPanel()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            s.$showPrimaryPane.map   { _ in () }.eraseToAnyPublisher(),
            s.$showClockCompanion.map { _ in () }.eraseToAnyPublisher(),
            s.$showWorkTimePane.map   { _ in () }.eraseToAnyPublisher(),
            s.$overlayMode.map       { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updatePaneLayout() }
        .store(in: &cancellables)

        s.$isFullScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fs in self?.applyFullScreen(fs, animate: true) }
            .store(in: &cancellables)

        s.$sizePreset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preset in
                guard let self = self, !self.s.isFullScreen else { return }
                self.applyPreset(preset, animate: false)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            s.$fontSize.map    { _ in () }.eraseToAnyPublisher(),
            s.$showSeconds.map { _ in () }.eraseToAnyPublisher(),
            s.$use24Hour.map   { _ in () }.eraseToAnyPublisher(),
            s.$showAmPm.map    { _ in () }.eraseToAnyPublisher(),
            s.$fontFamily.map  { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            guard let self = self,
                  !self.s.isFullScreen,
                  self.s.sizePreset != .custom else { return }
            self.applyPreset(self.s.sizePreset, animate: false)
        }
        .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handlePositionPreset(_:)),
            name: .moveToPreset, object: nil
        )
    }

    // MARK: - Full Screen

    func applyFullScreen(_ enable: Bool, animate: Bool) {
        guard let window = window, let screen = NSScreen.main else { return }
        if enable {
            if savedFrameBeforeFullscreen == nil {
                savedFrameBeforeFullscreen = window.frame
            }
            isApplyingProgrammaticFrame = true
            window.setFrame(screen.frame, display: true, animate: animate)
            isApplyingProgrammaticFrame = false
        } else {
            if let saved = savedFrameBeforeFullscreen {
                isApplyingProgrammaticFrame = true
                window.setFrame(saved, display: true, animate: animate)
                isApplyingProgrammaticFrame = false
                savedFrameBeforeFullscreen = nil
            } else {
                applyPreset(s.sizePreset, animate: animate)
            }
        }
        updateTransparencyPanel()
    }

    // MARK: - Size Presets

    func applyPreset(_ preset: SizePreset, animate: Bool) {
        guard let window = window else { return }

        if preset == .fullScreen {
            s.isFullScreen = true
            return
        }

        let paneSize: NSSize
        if preset == .custom {
            paneSize = NSSize(width: s.customWidth, height: s.customHeight)
        } else if let ps = preset.contentSize {
            paneSize = ps
        } else {
            return
        }

        let count = max(1, s.visiblePaneCount)
        let size = NSSize(width: paneSize.width * CGFloat(count), height: paneSize.height)
        isApplyingProgrammaticFrame = true
        window.setContentSize(size)
        isApplyingProgrammaticFrame = false
        if !isRestoringPosition {
            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = screenContaining(center) ?? nearestScreen(to: center) ?? NSScreen.main {
                var frame = window.frame
                frame.origin.x = min(frame.origin.x, screen.visibleFrame.maxX - frame.width)
                frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - frame.height)
                frame.origin.x = max(frame.origin.x, screen.visibleFrame.minX)
                frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY)
                window.setFrameOrigin(frame.origin)
            }
        }
    }

    // MARK: - Pane Layout

    private var paneSize: NSSize {
        if s.sizePreset == .custom {
            return NSSize(width: s.customWidth, height: s.customHeight)
        }
        if let ps = s.sizePreset.contentSize {
            return ps
        }
        return NSSize(width: s.customWidth, height: s.customHeight)
    }

    private func updatePaneLayout() {
        guard let window = window, !s.isFullScreen else { return }

        let newPanes = s.visiblePaneKinds
        let count = newPanes.count

        if count == 0 {
            lastVisiblePanes = []
            window.orderOut(nil)
            return
        }

        let pane = paneSize
        let newWidth = pane.width * CGFloat(count)
        let oldFrame = window.frame
        var origin = oldFrame.origin

        // Keep a surviving pane at its exact screen position when panes are
        // added or removed. The first shared pane is the reference; if a new
        // pane appears on the left, that shifts the window left instead.
        if !lastVisiblePanes.isEmpty {
            let shared = newPanes.first { lastVisiblePanes.contains($0) }
                ?? lastVisiblePanes.first { newPanes.contains($0) }
            if let shared,
               let oldIndex = lastVisiblePanes.firstIndex(of: shared),
               let newIndex = newPanes.firstIndex(of: shared) {
                let oldPaneWidth = oldFrame.width / CGFloat(max(1, lastVisiblePanes.count))
                let sharedX = oldFrame.origin.x + CGFloat(oldIndex) * oldPaneWidth
                origin.x = sharedX - CGFloat(newIndex) * pane.width
            }
        }

        isUpdatingPaneLayout = true
        window.setFrame(NSRect(origin: origin, size: NSSize(width: newWidth, height: pane.height)),
                        display: true)
        isUpdatingPaneLayout = false

        clampToScreen(window)
        lastVisiblePanes = newPanes

        if s.isVisible { window.orderFrontRegardless() }
        savePosition()
        updateTransparencyPanel()
    }

    private func clampToScreen(_ window: NSWindow) {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let screen = screenContaining(center) ?? nearestScreen(to: center) else { return }
        let vf = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, vf.minX), vf.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, vf.minY), vf.maxY - frame.height)
        suppressPositionSaves()
        window.setFrameOrigin(frame.origin)
    }

    // MARK: - Position Presets

    @objc private func handlePositionPreset(_ note: Notification) {
        if let preset = note.object as? ClockSettings.PositionPreset {
            moveToPreset(preset)
        }
    }

    func moveToPreset(_ preset: ClockSettings.PositionPreset, save: Bool = true) {
        guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
        let f = screen.visibleFrame
        let w = window.frame.width
        let h = window.frame.height
        let p: CGFloat = 20

        let origin: NSPoint
        switch preset {
        case .topCenter:   origin = NSPoint(x: f.midX - w/2,   y: f.maxY - h)
        case .topLeft:     origin = NSPoint(x: f.minX + p,     y: f.maxY - h - p)
        case .topRight:    origin = NSPoint(x: f.maxX - w - p, y: f.maxY - h - p)
        case .bottomLeft:  origin = NSPoint(x: f.minX + p,     y: f.minY + p)
        case .bottomRight: origin = NSPoint(x: f.maxX - w - p, y: f.minY + p)
        case .center:      origin = NSPoint(x: f.midX - w/2,   y: f.midY - h/2)
        case .reset:       origin = NSPoint(x: f.maxX - w - p, y: f.maxY - h - p)
        }

        if save {
            cancelPendingSavedScreenRestore()
            suppressPositionSaves()
        } else {
            suppressPositionSaves()
        }
        window.setFrameOrigin(origin)
        if save { savePosition(force: true) }
    }

    // Cycles the clock through the connected displays, keeping the same relative
    // spot (top-centre stays top-centre). Manual, deterministic escape hatch for
    // the cases where a wake does not restore the saved display by itself.
    func moveToNextScreen() {
        guard let window = window, !s.isFullScreen else { return }
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard screens.count > 1 else { return }

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let current = screenContaining(center) ?? window.screen,
              let index = screens.firstIndex(where: { Self.displayID(of: $0) == Self.displayID(of: current) })
        else { return }
        let target = screens[(index + 1) % screens.count]

        let origin = relativeOrigin(of: window, from: current, to: target)
        cancelPendingSavedScreenRestore()
        suppressPositionSaves()
        window.setFrameOrigin(origin)
        savePosition(force: true)
        PositionLog.write("manual screen switch -> \(target.localizedName) origin=\(Int(origin.x)),\(Int(origin.y))")
    }

    private func relativeOrigin(of window: NSWindow, from current: NSScreen, to target: NSScreen) -> NSPoint {
        let cf = current.visibleFrame
        let tf = target.visibleFrame
        let w = window.frame.width
        let h = window.frame.height

        let spanX = max(1, cf.width - w)
        let spanY = max(1, cf.height - h)
        let relX = min(max((window.frame.minX - cf.minX) / spanX, 0), 1)
        let relY = min(max((window.frame.minY - cf.minY) / spanY, 0), 1)

        return NSPoint(x: tf.minX + relX * max(0, tf.width - w),
                       y: tf.minY + relY * max(0, tf.height - h))
    }

    // MARK: - Burn-in Prevention

    private func setupBurnInPrevention() {
        s.$burnInPrevention
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.startBurnInTimer()
                } else {
                    self?.burnInTimer?.invalidate()
                    self?.burnInTimer = nil
                }
            }
            .store(in: &cancellables)

        s.$burnInInterval
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self, self.s.burnInPrevention else { return }
                self.startBurnInTimer()
            }
            .store(in: &cancellables)
    }

    // Click-through normally makes the overlay transparent to the mouse. When
    // the timer reaches zero, keep the overlay clickable so the user can start
    // the break with the same single click that acknowledges the alert. The
    // user's Click-Through preference is not changed.
    private func applyMousePassthrough() {
        guard let window = window else { return }
        let finishedTimerNeedsClick = TimeController.shared.timerState == .finished
        window.ignoresMouseEvents = s.isClickThrough && !finishedTimerNeedsClick
    }

    // MARK: - Transparency Button

    private func applyWindowOpacity() {
        guard let window = window else { return }
        let dimmed = s.quickDimmed ? min(s.windowOpacity, 0.32) : s.windowOpacity
        window.alphaValue = dimmed
    }

    private func setupTransparencyPanel() {
        guard transparencyPanel == nil, let window = window else { return }
        let panel = TransparencyPanel()
        transparencyPanel = panel
        window.addChildWindow(panel, ordered: .above)
        updateTransparencyPanel()
    }

    private func updateTransparencyPanel() {
        guard let window = window, let panel = transparencyPanel else { return }
        let shouldShow = s.isVisible && !s.isFullScreen && s.visiblePaneCount > 0
            && window.isVisible
        guard shouldShow else {
            panel.orderOut(nil)
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: window.frame.maxX - size.width,
                                     y: window.frame.minY))
        panel.orderFrontRegardless()
    }

    private func startBurnInTimer() {
        burnInTimer?.invalidate()
        let interval = max(30, s.burnInInterval)
        burnInTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.driftPosition()
        }
    }

    private func driftPosition() {
        guard let window = window, !s.isFullScreen, let screen = NSScreen.main else { return }
        let drift: CGFloat = 4
        burnInDirection *= -1
        let dx = CGFloat(burnInDirection) * drift
        let dy = CGFloat(burnInDirection) * drift

        var origin = window.frame.origin
        origin.x += dx
        origin.y += dy

        let vf = screen.visibleFrame
        origin.x = min(max(origin.x, vf.minX), vf.maxX - window.frame.width)
        origin.y = min(max(origin.y, vf.minY), vf.maxY - window.frame.height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.5
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrameOrigin(origin)
        }
        savePosition()
    }

    // MARK: - DVD Bounce

    private func setupDVDBounce() {
        s.$dvdBounce
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.startDVDBounce()
                } else {
                    self?.stopDVDBounce()
                }
            }
            .store(in: &cancellables)

        s.$dvdBounceSpeed
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speed in
                guard let self = self, self.s.dvdBounce else { return }
                let len = sqrt(self.dvdVelocity.x * self.dvdVelocity.x + self.dvdVelocity.y * self.dvdVelocity.y)
                if len > 0 {
                    self.dvdVelocity.x = self.dvdVelocity.x / len * speed
                    self.dvdVelocity.y = self.dvdVelocity.y / len * speed
                }
            }
            .store(in: &cancellables)
    }

    private func startDVDBounce() {
        stopDVDBounce(returnHome: false)
        guard let window = window else { return }
        savePosition()
        isDVDBouncing = true
        dvdPosition = CGPoint(x: window.frame.origin.x, y: window.frame.origin.y)
        let speed = s.dvdBounceSpeed
        let angle = Double.random(in: 0.3...1.2)
        dvdVelocity = CGPoint(x: speed * cos(angle), y: speed * sin(angle))
        dvdLastTimestamp = 0

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.dvdTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        dvdTimer = timer
    }

    private func stopDVDBounce(returnHome: Bool = true) {
        let wasBouncing = isDVDBouncing
        dvdTimer?.invalidate()
        dvdTimer = nil
        isDVDBouncing = false
        // Glide back to where the clock sat before bouncing began.
        guard returnHome, wasBouncing, let window = window, !s.isFullScreen,
              hasSavedPosition else { return }
        let home = NSRect(origin: NSPoint(x: s.windowX, y: s.windowY), size: window.frame.size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(home, display: true)
        }
    }

    private func dvdTick() {
        guard let window = window, !s.isFullScreen else { return }
        let now = CACurrentMediaTime()
        let dt: CGFloat
        if dvdLastTimestamp > 0 {
            dt = min(CGFloat(now - dvdLastTimestamp), 0.05) * 60.0
        } else {
            dt = 1.0
        }
        dvdLastTimestamp = now

        let w = window.frame.width
        let h = window.frame.height

        var newX = dvdPosition.x + dvdVelocity.x * dt
        var newY = dvdPosition.y + dvdVelocity.y * dt

        let clockRect = NSRect(x: newX, y: newY, width: w, height: h)

        // Find which screen the clock center is on (or nearest)
        let center = CGPoint(x: clockRect.midX, y: clockRect.midY)
        let currentScreen = screenContaining(center) ?? nearestScreen(to: center)
        guard let screen = currentScreen else { return }
        let vf = screen.visibleFrame

        // Bounce off edges of the current screen
        if newX < vf.minX {
            newX = vf.minX
            dvdVelocity.x = abs(dvdVelocity.x)
        } else if newX + w > vf.maxX {
            // Allow crossing to an adjacent screen
            let nextCenter = CGPoint(x: newX + w / 2, y: center.y)
            if let nextScreen = screenContaining(nextCenter), nextScreen != screen {
                // Moving onto another screen — don't bounce
            } else {
                newX = vf.maxX - w
                dvdVelocity.x = -abs(dvdVelocity.x)
            }
        }

        if newX < vf.minX {
            let nextCenter = CGPoint(x: newX + w / 2, y: center.y)
            if let nextScreen = screenContaining(nextCenter), nextScreen != screen {
                // Moving onto another screen — don't bounce
            } else {
                newX = vf.minX
                dvdVelocity.x = abs(dvdVelocity.x)
            }
        }

        if newY < vf.minY {
            newY = vf.minY
            dvdVelocity.y = abs(dvdVelocity.y)
        } else if newY + h > vf.maxY {
            newY = vf.maxY - h
            dvdVelocity.y = -abs(dvdVelocity.y)
        }

        // Safety: clamp to nearest screen so the clock never lands in a dead zone
        let finalCenter = CGPoint(x: newX + w / 2, y: newY + h / 2)
        if screenContaining(finalCenter) == nil {
            if let nearest = nearestScreen(to: finalCenter) {
                let sf = nearest.visibleFrame
                newX = min(max(newX, sf.minX), sf.maxX - w)
                newY = min(max(newY, sf.minY), sf.maxY - h)
            }
        }

        dvdPosition = CGPoint(x: newX, y: newY)
        window.setFrameOrigin(dvdPosition)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.contains(point) }
    }

    private func nearestScreen(to point: CGPoint) -> NSScreen? {
        NSScreen.screens.min(by: { distanceSq(point, $0.visibleFrame) < distanceSq(point, $1.visibleFrame) })
    }

    private func distanceSq(_ point: CGPoint, _ rect: NSRect) -> CGFloat {
        let cx = max(rect.minX, min(point.x, rect.maxX))
        let cy = max(rect.minY, min(point.y, rect.maxY))
        let dx = point.x - cx
        let dy = point.y - cy
        return dx * dx + dy * dy
    }

    // MARK: - Screen Identity

    // macOS can rename a display when it reconnects after a wake ("LG ULTRAWIDE"
    // may come back with a suffix). The hardware ID survives that, so it is the
    // primary key; the name stays as a fallback for older saved state.
    static func displayID(of screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    private func savedScreen() -> NSScreen? {
        if s.windowScreenID != 0,
           let byID = NSScreen.screens.first(where: { Self.displayID(of: $0) == s.windowScreenID }) {
            return byID
        }
        if !s.windowScreenName.isEmpty,
           let byName = NSScreen.screens.first(where: { $0.localizedName == s.windowScreenName }) {
            return byName
        }
        return nil
    }

    // MARK: - Persistence

    func savePosition(force: Bool = false) {
        // While bouncing, keep the pre-bounce spot as the saved position.
        guard let window = window, !isDVDBouncing else { return }
        // A display change can temporarily reflow the window onto another
        // screen. Do not persist that transient frame unless the user is
        // actively dragging or explicitly saving a new position.
        if !force && (pendingSavedScreenRestore || ignoreSystemPositionSaves) { return }
        let origin = window.frame.origin
        s.windowX = origin.x
        s.windowY = origin.y

        // Save position relative to the screen the clock is on
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if let screen = screenContaining(center) ?? nearestScreen(to: center) {
            let sf = screen.frame
            let id = Self.displayID(of: screen)
            if id != s.windowScreenID || screen.localizedName != s.windowScreenName {
                PositionLog.write("saved screen changed: \(screen.localizedName) id=\(id)")
            }
            s.windowScreenID      = id
            s.windowScreenOffsetX = origin.x - sf.origin.x
            s.windowScreenOffsetY = origin.y - sf.origin.y
            s.windowScreenName = screen.localizedName
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !s.isFullScreen, !isUpdatingPaneLayout, !isApplyingProgrammaticFrame else { return }
        updateTransparencyPanel()
        if let window = window {
            let paneCount = CGFloat(max(1, s.visiblePaneCount))
            s.customWidth  = Double(window.frame.width / paneCount)
            s.customHeight = Double(window.frame.height)
            if s.sizePreset != .custom { s.sizePreset = .custom }
        }
    }

    func windowDidMove(_ notification: Notification) {
        updateTransparencyPanel()
        guard !isDVDBouncing else { return }
        if isUserMovingWindow {
            ignoreSystemPositionSaves = false
            noteUserMove()
            cancelPendingSavedScreenRestore()
            savePosition(force: true)
            return
        }
        guard !isRestoringPosition, !isPositionSaveSuppressed, !pendingSavedScreenRestore else { return }
        savePosition()
    }

}

// Small rolling log for display/position decisions. A wake with a late external
// display is hard to reproduce, so the next occurrence leaves evidence instead
// of guesswork. Capped, plain text, no user content.
enum PositionLog {
    private static let maxBytes = 48_000

    private static let url: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("FloatingClockOverlay-position.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
            try? data.write(to: url)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func screenSummary() -> String {
        NSScreen.screens
            .map { "\($0.localizedName)#\(ClockWindowController.displayID(of: $0)) \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }
            .joined(separator: " | ")
    }
}

// MARK: - Custom Window (easier dragging)

class ClockWindow: NSWindow {
    private var pendingSingleClick: DispatchWorkItem?
    private let controlSize: CGFloat = 16
    private let controlInset: CGFloat = 8
    private let controlHitPadding: CGFloat = 4

    private struct PaneHitArea {
        let frame: NSRect
        let kind: OverlayPaneKind
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        let pane = paneHitArea(at: loc)
        NotificationCenter.default.post(name: .userInteraction, object: nil)

        if NSScreen.screens.count > 1, screenSwitchRect.contains(loc) {
            if event.clickCount == 1 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                NotificationCenter.default.post(name: .switchScreen, object: nil)
            }
            return
        }

        if let pane = pane, closeRect(for: pane).contains(loc) {
            if event.clickCount == 1 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                closePane(pane)
            }
            return
        }

        if let pane = pane, hasResetControl(pane), resetRect(for: pane).contains(loc) {
            if event.clickCount == 1 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                resetPane(pane)
            }
            return
        }

        if event.clickCount == 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            NotificationCenter.default.post(name: .openSettings, object: nil)
            return
        }

        guard event.clickCount == 1 else { return }

        let edge: CGFloat = 4
        let nearEdge = loc.x < edge || loc.x > frame.width - edge ||
                       loc.y < edge || loc.y > frame.height - edge
        if nearEdge {
            NotificationCenter.default.post(name: .userDragBegan, object: nil)
            super.mouseDown(with: event)
            return
        }

        let startOrigin = frame.origin
        NotificationCenter.default.post(name: .userDragBegan, object: nil)
        performDrag(with: event)
        scheduleSingleClick(from: startOrigin, togglesTimer: pane?.kind == .primary)
    }

    // Pane order matches ClockView.panes: work time, primary, clock companion.
    private var paneHitAreas: [PaneHitArea] {
        let settings = ClockSettings.shared
        let panes = settings.visiblePaneKinds
        guard !panes.isEmpty else { return [] }

        let width = frame.width / CGFloat(panes.count)
        return panes.enumerated().map { index, pane in
            PaneHitArea(
                frame: NSRect(x: CGFloat(index) * width, y: 0,
                              width: width, height: frame.height),
                kind: pane
            )
        }
    }

    private func paneHitArea(at point: NSPoint) -> PaneHitArea? {
        paneHitAreas.first { $0.frame.contains(point) }
    }

    private func closeRect(for pane: PaneHitArea) -> NSRect {
        NSRect(x: pane.frame.maxX - controlInset - controlSize,
               y: pane.frame.maxY - controlInset - controlSize,
               width: controlSize,
               height: controlSize)
            .insetBy(dx: -controlHitPadding, dy: -controlHitPadding)
    }

    private var screenSwitchRect: NSRect {
        NSRect(x: controlInset, y: controlInset, width: controlSize, height: controlSize)
            .insetBy(dx: -controlHitPadding, dy: -controlHitPadding)
    }

    private func resetRect(for pane: PaneHitArea) -> NSRect {
        NSRect(x: pane.frame.maxX - controlInset - controlSize,
               y: pane.frame.minY + controlInset,
               width: controlSize,
               height: controlSize)
            .insetBy(dx: -controlHitPadding, dy: -controlHitPadding)
    }

    private func hasResetControl(_ pane: PaneHitArea) -> Bool {
        switch pane.kind {
        case .workTime: return true
        case .primary:  return ClockSettings.shared.overlayMode != .clock
        case .clock:    return false
        }
    }

    private func scheduleSingleClick(from startOrigin: NSPoint, togglesTimer: Bool) {
        pendingSingleClick?.cancel()
        guard togglesTimer else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSingleClick = nil
            let dx = self.frame.origin.x - startOrigin.x
            let dy = self.frame.origin.y - startOrigin.y
            guard dx * dx + dy * dy < 4 else { return }
            guard ClockSettings.shared.overlayMode != .clock else { return }
            self.toggleTimerOrStopwatch()
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval,
                                      execute: work)
    }

    private func closePane(_ pane: PaneHitArea) {
        let settings = ClockSettings.shared
        switch pane.kind {
        case .workTime:
            settings.showWorkTimePane = false
        case .primary:
            settings.showPrimaryPane = false
        case .clock:
            settings.showClockCompanion = false
        }
    }

    private func toggleTimerOrStopwatch() {
        let tc = TimeController.shared
        switch ClockSettings.shared.overlayMode {
        case .timer:
            switch tc.timerState {
            case .idle:     tc.timerStart()
            case .running:  tc.timerPause()
            case .paused:   tc.timerStart()
            case .finished: tc.breakStart()
            case .breakRunning: tc.breakPause()
            case .breakPaused:  tc.breakResume()
            }
        case .stopwatch:
            switch tc.stopwatchState {
            case .idle:    tc.stopwatchStart()
            case .running: tc.stopwatchPause()
            case .paused:  tc.stopwatchStart()
            }
        case .clock:
            break
        }
    }

    private func resetPane(_ pane: PaneHitArea) {
        let tc = TimeController.shared
        switch pane.kind {
        case .workTime:
            if ClockSettings.shared.workStartManual {
                ClockSettings.shared.resetWorkTimeStart()
            } else {
                ClockSettings.shared.startWorkTimeNow()
            }
        case .primary:
            switch ClockSettings.shared.overlayMode {
            case .timer:     tc.timerReset()
            case .stopwatch: tc.stopwatchReset()
            case .clock:     break
            }
        case .clock:
            break
        }
    }
}

// The one control that must keep working in click-through mode, so it lives in
// its own panel instead of the clock window.
final class TransparencyPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = FirstMouseHostingView(rootView: TransparencyButtonView())
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
