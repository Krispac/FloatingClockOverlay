import SwiftUI

struct ClockView: View {
    @ObservedObject private var s  = ClockSettings.shared
    @ObservedObject private var tc = TimeController.shared

    @State private var clockTime = Date()
    @State private var flashOn   = true
    @State private var sampledBrightness: CGFloat = 0.0
    @State private var useWhiteText: Bool = true
    @State private var hostWindow: NSWindow?
    @State private var cardRect: CGRect?

    private let clockTimer = Timer.publish(every: 1.0,  on: .main, in: .common).autoconnect()
    private let flashTimer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    private let colorSampleTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if s.isFullScreen {
                // Full-screen: clock floats at the chosen alignment point
                ZStack(alignment: s.clockAlignment.swiftUIAlignment) {
                    Color.clear
                    clockCard.padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal: card always fills the entire window frame so
                // dragging any edge to resize also resizes the card.
                clockCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(clockTimer) { clockTime = $0 }
        .onReceive(colorSampleTimer) { _ in
            guard adaptiveApplies else { return }
            guard let hostWindow else { return }
            let screenBrightness = ScreenSampler.averageBrightness(under: hostWindow, cardRect: cardRect)
            guard screenBrightness >= 0 else { return }
            sampledBrightness = effectiveBrightness(overScreen: screenBrightness)
            if useWhiteText && sampledBrightness > 0.55 {
                useWhiteText = false
            } else if !useWhiteText && sampledBrightness < 0.45 {
                useWhiteText = true
            }
        }
        .onReceive(flashTimer) { _ in
            if s.overlayMode == .timer && tc.timerState == .finished {
                flashOn.toggle()
            } else {
                flashOn = true
            }
        }
    }

    // MARK: - Card

    // The card fills whatever frame the window gives it.
    // In click-through mode it looks exactly as before.
    // In interactive (drag/resize) mode it gains a dashed outline + corner
    // dots so the user can see the window boundary and resize handles.
    private var clockCard: some View {
        let style = s.selectedTheme.resolved(using: s)
        return ZStack {
            backgroundLayer(style)
            centeredContent(style)
            borderLayer(style)
            if !s.isClickThrough { resizeHandles }
        }
        // Tell the sampler where the card actually sits inside the window; in
        // full-screen mode the window is the whole display but the card is small.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardRect = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { cardRect = $0 }
            }
        )
        .background(WindowReader(window: $hostWindow))
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundLayer(_ style: ThemeStyle) -> some View {
        if s.selectedTheme == .weather {
            AnimatedThemeBackground(theme: .weather)
        } else if s.selectedTheme.isPopCulture {
            ZStack {
                RoundedRectangle(cornerRadius: style.cornerRadius)
                    .fill(style.bgColor.opacity(style.bgOpacity))
                AnimatedThemeBackground(theme: s.selectedTheme)
                    .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            }
        } else if s.selectedTheme == .standby {
            StandByBackground(cornerRadius: style.cornerRadius)
        } else if style.useGlass {
            iOSGlassCard(cornerRadius: style.cornerRadius)
        } else if style.bgOpacity > 0 {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(style.bgColor.opacity(style.bgOpacity))
        }
    }

    // MARK: - Text

    private func centeredContent(_ style: ThemeStyle) -> some View {
        VStack(spacing: 2) {
            Text(displayString)
                .font(.system(size: s.fontSize,
                              weight: s.fontWeight.weight,
                              design: s.fontFamily.design))
                .tracking(s.letterSpacing)
                .foregroundColor(activeTextColor(style))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .shadow(
                    color:  glowOrShadow(style, opacity: flashOn ? 0.9 : 0.4),
                    radius: style.useNeonGlow ? 10 : 3,
                    x: 0, y: style.useNeonGlow ? 0 : 1
                )
                .shadow(
                    color:  glowOrShadow(style, opacity: flashOn ? 0.5 : 0.2),
                    radius: style.useNeonGlow ? 22 : 8,
                    x: 0, y: style.useNeonGlow ? 0 : 4
                )

            if s.showDayOfWeek && s.overlayMode == .clock {
                Text(dayOfWeekString)
                    .font(.system(size: max(9, s.fontSize * 0.22),
                                  weight: .medium, design: s.fontFamily.design))
                    .foregroundStyle(activeTextColor(style).opacity(0.6))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }

            if s.selectedTheme == .weather {
                WeatherTemperatureLabel()
            }

            if s.overlayMode != .clock {
                Text(modeBadge)
                    .font(.system(size: max(9, s.fontSize * 0.18),
                                  weight: .medium, design: .monospaced))
                    .foregroundStyle(style.textColor.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Border

    @ViewBuilder
    private func borderLayer(_ style: ThemeStyle) -> some View {
        if style.borderOpacity > 0 {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(style.borderColor.opacity(style.borderOpacity), lineWidth: 1.5)
        }
    }

    // MARK: - Resize Handle Overlay
    // Shown only when click-through is OFF (interactive / drag-resize mode).
    // Gives the user a clear visual of where the window edges and corners are.

    private var resizeHandles: some View {
        ZStack {
            // Dashed outline = window boundary
            RoundedRectangle(cornerRadius: max(4, s.cornerRadius))
                .strokeBorder(
                    Color.white.opacity(0.55),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )

            // Corner dots = drag targets
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let r: CGFloat = 5
                let p: CGFloat = 5

                ForEach(
                    [CGPoint(x: p+r, y: p+r),
                     CGPoint(x: w-p-r, y: p+r),
                     CGPoint(x: p+r,   y: h-p-r),
                     CGPoint(x: w-p-r, y: h-p-r)],
                    id: \.x
                ) { pt in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.45), radius: 2)
                        .frame(width: r*2, height: r*2)
                        .position(pt)
                }
            }
        }
    }

    // MARK: - Display helpers

    private var displayString: String {
        switch s.overlayMode {
        case .clock:     return clockTimeString
        case .timer:     return tc.timerRemaining.hmsString
        case .stopwatch: return tc.stopwatchElapsed.hmsString
        }
    }

    private static let nativeNumberingSystems: [String: String] = [
        "ar": "arab",
        "hi": "deva",
        "bn": "beng",
        "fa": "arabext",
        "th": "thai",
        "my": "mymr",
    ]

    private var clockLocale: Locale {
        if s.clockLanguage.isEmpty { return Locale.current }
        if let ns = Self.nativeNumberingSystems[s.clockLanguage] {
            return Locale(identifier: "\(s.clockLanguage)@numbers=\(ns)")
        }
        return Locale(identifier: s.clockLanguage)
    }

    private var clockTimeString: String {
        let f = DateFormatter()
        f.locale = clockLocale
        if s.use24Hour {
            f.dateFormat = s.showSeconds ? "HH:mm:ss" : "HH:mm"
        } else if s.showAmPm {
            f.dateFormat = s.showSeconds ? "h:mm:ss a" : "h:mm a"
        } else {
            f.dateFormat = s.showSeconds ? "h:mm:ss" : "h:mm"
        }
        var result = f.string(from: clockTime)
        if !s.use24Hour && s.showAmPm && !s.amPmUppercase {
            result = result
                .replacingOccurrences(of: " AM", with: " am")
                .replacingOccurrences(of: " PM", with: " pm")
        }
        return result
    }

    private var dayOfWeekString: String {
        let f = DateFormatter()
        f.locale = clockLocale
        f.dateFormat = "EEEE"
        return f.string(from: clockTime)
    }

    private func activeTextColor(_ style: ThemeStyle) -> Color {
        if s.overlayMode == .timer && tc.timerState == .finished {
            return flashOn ? .red : style.textColor
        }
        if adaptiveApplies {
            return adaptiveTextColor
        }
        return style.textColor
    }

    private var adaptiveTextColor: Color {
        useWhiteText ? .white : .black
    }

    // Pop-culture themes paint opaque artwork behind the text, so the desktop colour
    // says nothing about the contrast actually seen. Weather is transparent, so it adapts.
    private var adaptiveApplies: Bool {
        s.adaptiveColor && !s.selectedTheme.isPopCulture
    }

    // The text is drawn on the theme's card, which is blended over the desktop.
    // Judge contrast against that blend, not the bare desktop behind it.
    private func effectiveBrightness(overScreen screen: CGFloat) -> CGFloat {
        let style = s.selectedTheme.resolved(using: s)
        guard !style.useGlass,
              let cardLuma = ScreenSampler.luminance(of: NSColor(style.bgColor)) else { return screen }
        let a = CGFloat(min(max(style.bgOpacity, 0), 1))
        return a * cardLuma + (1 - a) * screen
    }

    private func glowOrShadow(_ style: ThemeStyle, opacity: Double) -> Color {
        style.useNeonGlow
            ? style.glowColor.opacity(opacity)
            : Color.black.opacity(style.shadowOpacity * opacity)
    }

    private var modeBadge: String {
        switch s.overlayMode {
        case .clock: return ""
        case .timer:
            switch tc.timerState {
            case .running:  return "TIMER ▶"
            case .paused:   return "TIMER ⏸"
            case .finished: return "TIMER ✓"
            case .idle:     return "TIMER"
            }
        case .stopwatch:
            switch tc.stopwatchState {
            case .running: return "STOPWATCH ▶"
            case .paused:  return "STOPWATCH ⏸"
            case .idle:    return "STOPWATCH"
            }
        }
    }
}

// MARK: - Weather Temperature Label

struct WeatherTemperatureLabel: View {
    @ObservedObject private var ws = WeatherService.shared

    var body: some View {
        if ws.isLoaded {
            let p = ws.palette
            Text("\(p.emoji) \(ws.temperature)°")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(p.text.opacity(0.8))
                .shadow(color: p.glow.opacity(0.4), radius: 4)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
    }
}

// Hands a SwiftUI view the NSWindow it lives in, so each clock (including the
// mirrors on other displays) samples the screen behind its own window.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { window = v.window }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if v.window !== window { DispatchQueue.main.async { window = v.window } }
    }
}
