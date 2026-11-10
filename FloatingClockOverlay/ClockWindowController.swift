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
    private var dvdVelocity: CGPoint = CGPoint(x: 0.4, y: 0.3)
    private var dvdPosition: CGPoint = .zero
    private var isDVDBouncing = false
    private var isRestoringPosition = true
    private var dvdLastTimestamp: TimeInterval = 0
    private var lastPrimaryVisible = true
    private var lastCompanionVisible = false
    private var isUpdatingPaneLayout = false
    private var isApplyingProgrammaticFrame = false

    init() {
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
        lastPrimaryVisible = s.showPrimaryPane
        lastCompanionVisible = s.isClockCompanionVisible

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
    }

    // Monitors left of or below the main display have negative coordinates, so
    // "has a saved position" can't be judged by sign.
    private var hasSavedPosition: Bool { UserDefaults.standard.object(forKey: "windowX") != nil }

    private func restorePosition() {
        guard let window = window else { return }
        if restoreToSavedScreen(window) { return }
        restoreFallback(window)

        // The saved monitor may connect a few seconds after login; keep trying for
        // 10s unless the user has moved the clock in the meantime.
        guard !s.windowScreenName.isEmpty else { return }
        let placed = window.frame.origin
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            attempts += 1
            guard let self = self, let window = self.window, window.frame.origin == placed, attempts <= 10 else {
                timer.invalidate(); return
            }
            if self.restoreToSavedScreen(window) { timer.invalidate() }
        }
    }

    private func restoreToSavedScreen(_ window: NSWindow) -> Bool {
        guard !s.windowScreenName.isEmpty,
              let targetScreen = NSScreen.screens.first(where: { $0.localizedName == s.windowScreenName })
        else { return false }
        let origin = NSPoint(x: targetScreen.frame.origin.x + s.windowScreenOffsetX,
                             y: targetScreen.frame.origin.y + s.windowScreenOffsetY)
        guard targetScreen.visibleFrame.intersects(NSRect(origin: origin, size: window.frame.size)) else { return false }
        isRestoringPosition = true
        window.setFrameOrigin(origin)
        isRestoringPosition = false
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
        isRestoringPosition = true
        moveToPreset(.topRight, save: false)
        isRestoringPosition = false
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
    }

    @objc private func bringToFront() {
        guard s.isVisible, s.visiblePaneCount > 0 else { return }
        // Small delay so the newly activated app finishes raising its own windows first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            // orderFrontRegardless bypasses the normal "active app" restriction.
            self?.window?.orderFrontRegardless()
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        s.$isClickThrough
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ct in
                // .resizable stays in the mask always — mouse events are what
                // control whether the user can interact (drag/resize).
                self?.window?.ignoresMouseEvents = ct
            }
            .store(in: &cancellables)

        s.$windowOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.window?.alphaValue = $0 }
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
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            s.$showPrimaryPane.map   { _ in () }.eraseToAnyPublisher(),
            s.$showClockCompanion.map { _ in () }.eraseToAnyPublisher(),
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

        let primary = s.showPrimaryPane
        let companion = s.isClockCompanionVisible
        let count = s.visiblePaneCount

        if count == 0 {
            lastPrimaryVisible = false
            lastCompanionVisible = false
            window.orderOut(nil)
            return
        }

        let pane = paneSize
        let newWidth = pane.width * CGFloat(count)
        let oldFrame = window.frame
        var origin = oldFrame.origin

        // Keep the surviving pane where it was when the other one is closed.
        if lastPrimaryVisible && lastCompanionVisible {
            if !primary && companion {
                // Closing the left pane keeps the clock pane where it was.
                origin.x += oldFrame.width - newWidth
            }
        } else if !lastPrimaryVisible && lastCompanionVisible {
            if primary && companion {
                // The primary pane is added on the left; the clock stays in place.
                origin.x -= pane.width
            }
        }

        isUpdatingPaneLayout = true
        window.setFrame(NSRect(origin: origin, size: NSSize(width: newWidth, height: pane.height)),
                        display: true)
        isUpdatingPaneLayout = false

        clampToScreen(window)
        lastPrimaryVisible = primary
        lastCompanionVisible = companion

        if s.isVisible { window.orderFrontRegardless() }
        savePosition()
    }

    private func clampToScreen(_ window: NSWindow) {
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        guard let screen = screenContaining(center) ?? nearestScreen(to: center) else { return }
        let vf = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = min(max(frame.origin.x, vf.minX), vf.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, vf.minY), vf.maxY - frame.height)
        window.setFrameOrigin(frame.origin)
    }

    // MARK: - Position Presets

    @objc private func handlePositionPreset(_ note: Notification) {
        if let preset = note.object as? ClockSettings.PositionPreset {
            moveToPreset(preset)
        }
    }

    func moveToPreset(_ preset: ClockSettings.PositionPreset, save: Bool = true) {
        guard let window = window, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w = window.frame.width
        let h = window.frame.height
        let p: CGFloat = 20

        let origin: NSPoint
        switch preset {
        case .topLeft:     origin = NSPoint(x: f.minX + p,     y: f.maxY - h - p)
        case .topRight:    origin = NSPoint(x: f.maxX - w - p, y: f.maxY - h - p)
        case .bottomLeft:  origin = NSPoint(x: f.minX + p,     y: f.minY + p)
        case .bottomRight: origin = NSPoint(x: f.maxX - w - p, y: f.minY + p)
        case .center:      origin = NSPoint(x: f.midX - w/2,   y: f.midY - h/2)
        case .reset:       origin = NSPoint(x: f.maxX - w - p, y: f.maxY - h - p)
        }

        window.setFrameOrigin(origin)
        if save { savePosition() }
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

    // MARK: - Persistence

    func savePosition() {
        // While bouncing, keep the pre-bounce spot as the saved position.
        guard let window = window, !isDVDBouncing else { return }
        let origin = window.frame.origin
        s.windowX = origin.x
        s.windowY = origin.y

        // Save position relative to the screen the clock is on
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        if let screen = screenContaining(center) ?? nearestScreen(to: center) {
            let sf = screen.frame
            s.windowScreenOffsetX = origin.x - sf.origin.x
            s.windowScreenOffsetY = origin.y - sf.origin.y
            s.windowScreenName = screen.localizedName
        }
        UserDefaults.standard.synchronize()
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard !s.isFullScreen, !isUpdatingPaneLayout, !isApplyingProgrammaticFrame else { return }
        if let window = window {
            let paneCount = CGFloat(max(1, s.visiblePaneCount))
            s.customWidth  = Double(window.frame.width / paneCount)
            s.customHeight = Double(window.frame.height)
            if s.sizePreset != .custom { s.sizePreset = .custom }
        }
    }

    func windowDidMove(_ notification: Notification) {
        if !isDVDBouncing && !isRestoringPosition {
            savePosition()
        }
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
        let mode: OverlayMode
        let isPrimary: Bool
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        let pane = paneHitArea(at: loc)

        if let pane = pane, closeRect(for: pane).contains(loc) {
            if event.clickCount == 1 {
                pendingSingleClick?.cancel()
                pendingSingleClick = nil
                closePane(pane)
            }
            return
        }

        if let pane = pane, pane.mode != .clock, resetRect(for: pane).contains(loc) {
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
            super.mouseDown(with: event)
            return
        }

        let startOrigin = frame.origin
        performDrag(with: event)
        scheduleSingleClick(from: startOrigin, togglesTimer: pane?.isPrimary == true)
    }

    // Pane order matches ClockView.panes: primary first, clock companion second.
    private var paneHitAreas: [PaneHitArea] {
        let settings = ClockSettings.shared
        var panes: [(OverlayMode, Bool)] = []
        if settings.showPrimaryPane {
            panes.append((settings.overlayMode, true))
        }
        if settings.isClockCompanionVisible {
            panes.append((.clock, false))
        }
        guard !panes.isEmpty else { return [] }

        let width = frame.width / CGFloat(panes.count)
        return panes.enumerated().map { index, pane in
            PaneHitArea(
                frame: NSRect(x: CGFloat(index) * width, y: 0,
                              width: width, height: frame.height),
                mode: pane.0,
                isPrimary: pane.1
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

    private func resetRect(for pane: PaneHitArea) -> NSRect {
        NSRect(x: pane.frame.maxX - controlInset - controlSize,
               y: pane.frame.minY + controlInset,
               width: controlSize,
               height: controlSize)
            .insetBy(dx: -controlHitPadding, dy: -controlHitPadding)
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
        if pane.isPrimary {
            settings.showPrimaryPane = false
        } else {
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
            case .finished: tc.timerReset(); tc.timerStart()
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
        switch pane.mode {
        case .timer:     tc.timerReset()
        case .stopwatch: tc.stopwatchReset()
        case .clock:     break
        }
    }
}
