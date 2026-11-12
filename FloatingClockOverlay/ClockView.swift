import SwiftUI

struct ClockView: View {
    @ObservedObject private var s  = ClockSettings.shared
    @ObservedObject private var tc = TimeController.shared

    @State private var clockTime = Date()
    @State private var flashOn   = true
    @State private var colonVisible = true
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
        .onReceive(clockTimer) {
            clockTime = $0
            colonVisible.toggle()
        }
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

    private struct Pane: Identifiable {
        let kind: OverlayPaneKind
        var id: String { kind.rawValue }

        var mode: OverlayMode? {
            switch kind {
            case .workTime: return nil
            case .primary:  return ClockSettings.shared.overlayMode
            case .clock:    return .clock
            }
        }
    }

    private var panes: [Pane] {
        s.visiblePaneKinds.map { Pane(kind: $0) }
    }

    // The card fills whatever frame the window gives it. When both panes are
    // visible they share one continuous theme surface and move as one window.
    private var clockCard: some View {
        let style = s.selectedTheme.resolved(using: s)
        let panes = self.panes
        return ZStack {
            backgroundLayer(style, paneCount: max(1, panes.count))

            if s.verticalLayout {
                VStack(spacing: 0) {
                    ForEach(panes) { pane in
                        paneContent(pane, style)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(panes) { pane in
                        paneContent(pane, style)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            if panes.count > 1 {
                GeometryReader { geo in
                    ForEach(1..<panes.count, id: \.self) { index in
                        if s.verticalLayout {
                            Rectangle()
                                .fill(style.textColor.opacity(0.10))
                                .frame(width: max(0, geo.size.width - 20), height: 1)
                                .position(
                                    x: geo.size.width / 2,
                                    y: geo.size.height * CGFloat(index) / CGFloat(panes.count)
                                )
                        } else {
                            Rectangle()
                                .fill(style.textColor.opacity(0.10))
                                .frame(width: 1, height: max(0, geo.size.height - 20))
                                .position(
                                    x: geo.size.width * CGFloat(index) / CGFloat(panes.count),
                                    y: geo.size.height / 2
                                )
                        }
                    }
                }
            }

            if s.verticalLayout {
                VStack(spacing: 0) {
                    ForEach(panes) { pane in
                        paneControls(pane, style, isLastPane: pane.id == panes.last?.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(false)
            } else {
                HStack(spacing: 0) {
                    ForEach(panes) { pane in
                        paneControls(pane, style, isLastPane: pane.id == panes.last?.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .allowsHitTesting(false)
            }

            if NSScreen.screens.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        switchScreenControl(style)
                        Spacer()
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }

            borderLayer(style)
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
    private func backgroundLayer(_ style: ThemeStyle, paneCount: Int) -> some View {
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
            StandByBackground(cornerRadius: style.cornerRadius, paneCount: paneCount)
        } else if style.useGlass {
            iOSGlassCard(cornerRadius: style.cornerRadius)
        } else if style.bgOpacity > 0 {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(style.bgColor.opacity(style.bgOpacity))
        }
    }

    // MARK: - Pane content

    @ViewBuilder
    private func paneContent(_ pane: Pane, _ style: ThemeStyle) -> some View {
        if s.verticalLayout {
            switch pane.kind {
            case .workTime:
                verticalWorkTimePaneContent(style)
            case .primary, .clock:
                verticalStandardPaneContent(mode: pane.mode ?? .clock, style: style)
            }
        } else {
            switch pane.kind {
            case .workTime:
                workTimePaneContent(style)
            case .primary, .clock:
                standardPaneContent(mode: pane.mode ?? .clock, style: style)
            }
        }
    }

    // MARK: - Vertical panes (narrow strip, values stacked in two lines)

    private func verticalValue(_ text: String, style: ThemeStyle, size: CGFloat,
                               color: Color, glowOn: Bool) -> some View {
        verticalValueText(Text(text), style: style, size: size, color: color, glowOn: glowOn)
    }

    private func verticalValueText(_ text: Text, style: ThemeStyle, size: CGFloat,
                                   color: Color, glowOn: Bool) -> some View {
        // The horizontal glow radii (10/22) are tuned for the full-size digits.
        // On the smaller stacked digits they merge into one blob, so the
        // vertical strip gets its own, much tighter halo.
        let inner: CGFloat = style.useNeonGlow ? 5 : 2
        let outer: CGFloat = style.useNeonGlow ? 11 : 5
        return text
            .font(.system(size: size, weight: timeWeight, design: timeDesign)
                    .monospacedDigit())
            .tracking(timeTracking)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .shadow(
                color: glowOrShadow(style, opacity: glowOn ? 0.9 : 0.4),
                radius: inner,
                x: 0, y: style.useNeonGlow ? 0 : 1
            )
            .shadow(
                color: glowOrShadow(style, opacity: glowOn ? 0.5 : 0.2),
                radius: outer,
                x: 0, y: style.useNeonGlow ? 0 : 4
            )
    }

    private func verticalUnit(_ text: String, style: ThemeStyle,
                              size: CGFloat, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: badgeDesign))
            .foregroundStyle(style.textColor.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.35)
    }

    // Hours over minutes over seconds, like a flip clock. A unit that the
    // horizontal pane already shows ("h") stays attached to its value; nothing
    // new is introduced.
    private func verticalRows(_ rows: [(value: String, unit: String?)],
                              style: ThemeStyle, size: CGFloat,
                              color: Color, glowOn: Bool) -> some View {
        let unitSize = max(10, size * 0.38)
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                // The unit floats next to the digits instead of taking part in
                // the layout, so every line stays on the same vertical axis.
                verticalValue(row.value, style: style, size: size,
                              color: color, glowOn: glowOn)
                    .overlay(alignment: .trailing) {
                        if let unit = row.unit {
                            verticalUnit(unit, style: style, size: unitSize, opacity: 0.6)
                                .offset(x: unitSize * 0.9)
                        }
                    }
            }
        }
    }

    private func verticalStandardPaneContent(mode: OverlayMode, style: ThemeStyle) -> some View {
        let flashing = mode == .timer && tc.timerState == .finished
        let glowOn = flashing ? flashOn : true
        let color = activeTextColor(style, mode: mode)

        var rows: [(value: String, unit: String?)] = []
        var size = s.fontSize * 0.62

        switch mode {
        case .clock:
            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: clockTime)
            let rawHour = comps.hour ?? 0
            let hour = s.use24Hour ? rawHour : (rawHour % 12 == 0 ? 12 : rawHour % 12)
            rows = [(String(format: "%02d", hour), nil),
                    (String(format: "%02d", comps.minute ?? 0), nil)]
            if s.showSeconds {
                rows.append((String(format: "%02d", comps.second ?? 0), nil))
                size = s.fontSize * 0.52
            }
        case .timer, .stopwatch:
            let seconds = mode == .timer
                ? Int(max(0, tc.timerState == .finished ? tc.timerOvertime : tc.timerRemaining))
                : Int(max(0, tc.stopwatchElapsed))
            // Same information as the horizontal pane: hours, minutes, seconds.
            rows = [(String(format: "%02d", seconds / 3600), nil),
                    (String(format: "%02d", (seconds % 3600) / 60), nil),
                    (String(format: "%02d", seconds % 60), nil)]
            size = s.fontSize * 0.52
        }

        return VStack(alignment: .leading, spacing: 6) {
            // Label in the top-left corner; the corner buttons stay free.
            verticalUnit(mode == .clock ? " " : modeBadge(for: mode), style: style,
                         size: max(9, s.fontSize * 0.17), opacity: 0.5)
            if mode == .clock {
                // One row, like the horizontal clock, with the same gentle
                // colon fade.
                verticalValueText(displayText(for: .clock, style: style),
                                  style: style, size: size, color: color, glowOn: glowOn)
                    .animation(.easeInOut(duration: 0.55), value: colonVisible)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                verticalRows(rows, style: style, size: size, color: color, glowOn: glowOn)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func verticalWorkTimePaneContent(_ style: ThemeStyle) -> some View {
        let roundedMinutes = s.workElapsedRoundedMinutes(now: clockTime)
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        let valueColor = s.adaptiveColor ? adaptiveTextColor : style.textColor

        return VStack(alignment: .leading, spacing: 6) {
            verticalUnit(s.workStartClockString(now: clockTime),
                         style: style, size: max(9, s.fontSize * 0.18), opacity: 0.55)
            verticalRows([(String(format: "%02d", hours), "h"),
                          (String(format: "%02d", minutes), nil)],
                         style: style, size: s.fontSize * 0.62,
                         color: valueColor, glowOn: true)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 5)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func standardPaneContent(mode: OverlayMode, style: ThemeStyle) -> some View {
        let flashing = mode == .timer && tc.timerState == .finished
        let glowOn = flashing ? flashOn : true

        return VStack(spacing: 2) {
            displayText(for: mode, style: style)
                .font(.system(size: s.fontSize,
                              weight: timeWeight,
                              design: timeDesign)
                      .monospacedDigit())
                .tracking(timeTracking)
                .foregroundColor(activeTextColor(style, mode: mode))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .animation(.easeInOut(duration: 0.55), value: colonVisible)
                .shadow(
                    color:  glowOrShadow(style, opacity: glowOn ? 0.9 : 0.4),
                    radius: style.useNeonGlow ? 10 : 3,
                    x: 0, y: style.useNeonGlow ? 0 : 1
                )
                .shadow(
                    color:  glowOrShadow(style, opacity: glowOn ? 0.5 : 0.2),
                    radius: style.useNeonGlow ? 22 : 8,
                    x: 0, y: style.useNeonGlow ? 0 : 4
                )

            if s.showDayOfWeek && mode == .clock {
                Text(dayOfWeekString)
                    .font(.system(size: max(9, s.fontSize * 0.22),
                                  weight: .medium, design: labelDesign))
                    .foregroundStyle(activeTextColor(style, mode: mode).opacity(0.6))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }

            if s.selectedTheme == .weather && mode == .clock {
                WeatherTemperatureLabel()
            }

            if mode != .clock {
                Text(modeBadge(for: mode))
                    .font(.system(size: max(9, s.fontSize * 0.18),
                                  weight: .medium, design: badgeDesign))
                    .tracking(badgeTracking)
                    .foregroundStyle(style.textColor.opacity(0.5))
            }
        }
        // A vertical pane is only as wide as the horizontal bar is high, so it
        // needs every point of width for the digits.
        .padding(.horizontal, s.verticalLayout ? 4 : 16)
        .padding(.vertical, s.verticalLayout ? 4 : 8)
    }

    // The clock's colon fades gently instead of hard-blinking.
    private func displayText(for mode: OverlayMode, style: ThemeStyle) -> Text {
        guard mode == .clock else { return Text(displayString(for: mode)) }
        let parts = clockTimeString.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return Text(clockTimeString) }
        let colon = activeTextColor(style, mode: mode).opacity(colonVisible ? 1 : 0.22)
        var text = Text(parts[0]) + Text(":").foregroundColor(colon)
        if parts.count > 2 {
            text = text + Text(parts[1] + ":" + parts[2])
        } else {
            text = text + Text(parts[1])
        }
        return text
    }

    private func workTimePaneContent(_ style: ThemeStyle) -> some View {
        let roundedMinutes = s.workElapsedRoundedMinutes(now: clockTime)
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        let valueColor = s.adaptiveColor ? adaptiveTextColor : style.textColor

        return VStack(spacing: 2) {
            Text(s.verticalLayout
                 ? String(format: "%d:%02d", hours, minutes)
                 : String(format: "%d:%02d h", hours, minutes))
                .font(.system(size: s.fontSize * 0.72,
                              weight: timeWeight,
                              design: timeDesign)
                      .monospacedDigit())
                .tracking(timeTracking)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.34)
                .lineLimit(1)
                .shadow(
                    color: glowOrShadow(style, opacity: 0.5),
                    radius: style.useNeonGlow ? 10 : 3,
                    x: 0, y: style.useNeonGlow ? 0 : 1
                )

            Text("START \(s.workStartClockString(now: clockTime))")
                .font(.system(size: max(9, s.fontSize * 0.2),
                              weight: .medium,
                              design: labelDesign)
                      .monospacedDigit())
                .tracking(badgeTracking)
                .foregroundStyle(valueColor.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .padding(.horizontal, s.verticalLayout ? 4 : 16)
        .padding(.vertical, s.verticalLayout ? 4 : 8)
    }

    // Visual only: ClockWindow owns the hit areas so it can distinguish
    // close/reset from a click-to-toggle and from dragging.
    private func paneControls(_ pane: Pane, _ style: ThemeStyle, isLastPane: Bool = false) -> some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    closeControl(style)
                }
                Spacer()
            }
            .padding(8)

            if pane.kind == .workTime ||
               (pane.kind == .primary && s.overlayMode != .clock) {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        bottomControl(pane, style)
                    }
                    .padding(.trailing, isLastPane && !s.verticalLayout ? 24 : 0)
                }
                .padding(8)
            }
        }
    }

    private func closeControl(_ style: ThemeStyle) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(style.textColor.opacity(0.68))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(style.textColor.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    @ViewBuilder
    private func bottomControl(_ pane: Pane, _ style: ThemeStyle) -> some View {
        if pane.kind == .workTime && !s.workStartManual {
            startNowControl(style)
        } else {
            resetControl(style)
        }
    }

    private func resetControl(_ style: ThemeStyle) -> some View {
        Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(style.textColor.opacity(0.68))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(style.textColor.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    private func startNowControl(_ style: ThemeStyle) -> some View {
        Image(systemName: "play.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(style.textColor.opacity(0.78))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.white.opacity(0.09)))
            .overlay(Circle().strokeBorder(style.textColor.opacity(0.20), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    private func switchScreenControl(_ style: ThemeStyle) -> some View {
        Image(systemName: "rectangle.on.rectangle")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(style.textColor.opacity(0.68))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.white.opacity(0.07)))
            .overlay(Circle().strokeBorder(style.textColor.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }

    // MARK: - Border

    @ViewBuilder
    private func borderLayer(_ style: ThemeStyle) -> some View {
        if style.borderOpacity > 0 {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .strokeBorder(style.borderColor.opacity(style.borderOpacity), lineWidth: 1.5)
        }
    }

    // MARK: - Display helpers

    private func displayString(for mode: OverlayMode) -> String {
        switch mode {
        case .clock:     return clockTimeString
        case .timer:
            // Finished = count up the delay before the break, so it is obvious
            // how long the "finish this first" window has been open.
            let value = tc.timerState == .finished ? tc.timerOvertime : tc.timerRemaining
            // The narrow vertical pane has room for MM:SS, not HH:MM:SS.
            return s.verticalLayout ? value.mmssString : value.hmsString
        case .stopwatch: return s.verticalLayout ? tc.stopwatchElapsed.mmssString : tc.stopwatchElapsed.hmsString
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

    private func activeTextColor(_ style: ThemeStyle, mode: OverlayMode) -> Color {
        if mode == .timer && tc.timerState == .finished {
            return flashOn ? .red : style.textColor
        }
        if adaptiveApplies {
            return adaptiveTextColor
        }
        return style.textColor
    }

    // StandBy is a designed theme: Apple-style SF Pro Regular with tabular digits.
    // Other themes keep the user's font family and weight.
    private var isStandByTheme: Bool { s.selectedTheme == .standby }
    private var timeDesign: Font.Design { isStandByTheme ? .default : s.fontFamily.design }
    private var timeWeight: Font.Weight { isStandByTheme ? .regular : s.fontWeight.weight }
    private var timeTracking: Double { isStandByTheme ? max(1.0, s.letterSpacing) : s.letterSpacing }
    private var labelDesign: Font.Design { isStandByTheme ? .default : s.fontFamily.design }
    private var badgeDesign: Font.Design { isStandByTheme ? .default : .monospaced }
    private var badgeTracking: Double { isStandByTheme ? 1.2 : 0 }

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

    private func modeBadge(for mode: OverlayMode) -> String {
        switch mode {
        case .clock: return ""
        case .timer:
            switch tc.timerState {
            case .running:  return "TIMER ▶"
            case .paused:   return "TIMER ⏸"
            case .finished: return "TIMER ✓"
            case .idle:     return "TIMER"
            case .breakRunning: return "BREAK ▶"
            case .breakPaused:  return "BREAK ⏸"
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

// Lives in its own tiny non-activating panel so it stays clickable even when
// the clock itself is in click-through mode.
struct ClickThroughButtonView: View {
    @ObservedObject private var s = ClockSettings.shared

    var body: some View {
        let style = s.selectedTheme.resolved(using: s)
        let symbol = s.isClickThrough ? "eye.slash" : "eye"
        let tint = style.textColor

        ZStack {
            Circle()
                .fill(Color.white.opacity(0.07))
            Circle()
                .strokeBorder(tint.opacity(0.16), lineWidth: 0.5)
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tint.opacity(0.68))
        }
        .frame(width: 16, height: 16)
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(name: .toggleClickThrough, object: nil)
        }
        .help(s.isClickThrough ? "Let the clock take clicks" : "Let clicks pass through")
    }
}
