import SwiftUI

// MARK: - Root Settings View

struct SettingsView: View {
    @ObservedObject private var s = ClockSettings.shared
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates = true

    private enum Tab: String, CaseIterable, Identifiable {
        case clock, look, window, general
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .clock:   return "Clock"
            case .look:    return "Look"
            case .window:  return "Window"
            case .general: return "General"
            }
        }
        var icon: String {
            switch self {
            case .clock:   return "clock"
            case .look:    return "paintpalette"
            case .window:  return "macwindow"
            case .general: return "gearshape"
            }
        }
    }

    @AppStorage("settings.selectedTab") private var tab: Tab = .clock
    @State private var showMoreLook = false

    var body: some View {
        VStack(spacing: 0) {
            quickBar
            tabBar
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .clock:
                        modeSection
                        timeSection
                    case .look:
                        themeSection
                        textSection
                    case .window:
                        sizeSection
                        behaviorSection
                        movementSection
                    case .general:
                        generalSection
                        aboutSection
                        quitButton
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Quick bar

    private var quickBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                QuickToggle(icon: s.isVisible ? "eye" : "eye.slash", label: "Show",
                            isOn: $s.isVisible)
                QuickToggle(icon: "cursorarrow.rays", label: "Click-Through",
                            isOn: $s.isClickThrough)
                QuickToggle(icon: "circle.lefthalf.filled", label: "Adaptive",
                            isOn: Binding(get: { s.adaptiveColor }, set: {
                                s.adaptiveColor = $0
                                if $0 { ScreenSampler.requestPermissionIfNeeded() }
                            }))
                QuickToggle(icon: "24.circle", label: "24-hour", isOn: $s.use24Hour)
                QuickToggle(icon: "timer", label: "Seconds", isOn: $s.showSeconds)
            }
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { s.isFullScreen ? nil : s.sizePreset },
                                              set: { if let p = $0 { s.isFullScreen = false; s.sizePreset = p } })) {
                    ForEach([SizePreset.small, .medium, .large, .extraLarge], id: \.self) { p in
                        Text(p.label).tag(Optional(p))
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                Picker("", selection: $s.selectedTheme) {
                    ForEach(ClockTheme.allCases) { t in Text(t.label).tag(t) }
                }
                .labelsHidden().frame(width: 120)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 17))
                        Text(t.title).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(tab == t ? Color.accentColor.opacity(0.15) : .clear))
                    .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Clock tab

    private var modeSection: some View {
        SettingsCard(label: "MODE", icon: "square.3.layers.3d") {
            VStack(spacing: 0) {
                Picker("", selection: $s.overlayMode) {
                    ForEach(OverlayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)

                if s.overlayMode != .clock {
                    Divider()
                    TimerStopwatchControlsView()
                        .padding(12)
                }
            }
        }
    }

    private var timeSection: some View {
        SettingsCard(label: "TIME FORMAT", icon: "clock.badge") {
            VStack(spacing: 0) {
                SettingsRow(icon: "clock.badge", label: "Hour Format") {
                    Picker("", selection: $s.use24Hour) {
                        Text("12-hour").tag(false)
                        Text("24-hour").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                }
                SettingsDivider()
                ToggleRow(icon: "timer", label: "Show Seconds", value: $s.showSeconds)
                if !s.use24Hour {
                    SettingsDivider()
                    ToggleRow(icon: "a.magnify", label: "Show AM/PM", value: $s.showAmPm)
                    if s.showAmPm {
                        SettingsDivider()
                        SettingsRow(icon: "textformat.abc", label: "AM/PM Style") {
                            Picker("", selection: $s.amPmUppercase) {
                                Text("AM / PM").tag(true)
                                Text("am / pm").tag(false)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                        }
                    }
                }
                SettingsDivider()
                ToggleRow(icon: "calendar", label: "Show Day of Week", value: $s.showDayOfWeek)
                SettingsDivider()
                SettingsRow(icon: "globe", label: "Clock Language") {
                    Picker("", selection: $s.clockLanguage) {
                        Text(NSLocalizedString("System Default", comment: "")).tag("")
                        Text("English").tag("en")
                        Text("Español").tag("es")
                        Text("العربية").tag("ar")
                        Text("বাংলা").tag("bn")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                        Text("日本語").tag("ja")
                        Text("中文").tag("zh")
                        Text("한국어").tag("ko")
                        Text("Português").tag("pt")
                        Text("Русский").tag("ru")
                        Text("हिन्दी").tag("hi")
                        Text("Türkçe").tag("tr")
                        Text("Italiano").tag("it")
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
        }
    }

    // MARK: Look tab

    private var themeSection: some View {
        SettingsCard(label: "THEME", icon: "theatermasks") {
            VStack(spacing: 0) {
                // Theme picker
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "theatermasks").frame(width: 20).foregroundStyle(.secondary)
                        Text("Theme").font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ClockTheme.allCases.filter { !$0.isPopCulture }) { theme in
                                ThemeCard(theme: theme, selected: s.selectedTheme == theme)
                                    .onTapGesture { s.selectedTheme = theme }
                            }
                        }
                        .padding(.horizontal, 12)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").frame(width: 20).foregroundStyle(.secondary)
                        Text("Pop Culture").font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ClockTheme.allCases.filter { $0.isPopCulture }) { theme in
                                ThemeCard(theme: theme, selected: s.selectedTheme == theme)
                                    .onTapGesture { s.selectedTheme = theme }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 10)

                    if s.selectedTheme == .f1 {
                        HStack(spacing: 8) {
                            Image(systemName: "flag.checkered").frame(width: 20).foregroundStyle(.secondary)
                            Text("F1 Team").font(.callout)
                        }
                        .padding(.horizontal, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(F1Team.allCases) { team in
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(team.carColor)
                                            .frame(width: 44, height: 28)
                                            .overlay(
                                                Text(team.number)
                                                    .font(.system(size: 11, weight: .heavy))
                                                    .foregroundColor(.white)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .strokeBorder(s.f1Team == team ? Color.white : Color.clear, lineWidth: 2)
                                            )
                                        Text(team.label)
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(s.f1Team == team ? .primary : .secondary)
                                    }
                                    .onTapGesture { s.f1Team = team }
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(.bottom, 10)
                    }
                }

            }
        }
    }

    private var textSection: some View {
        SettingsCard(label: "TEXT & COLORS", icon: "textformat") {
            VStack(spacing: 0) {
                SettingsRow(icon: "character.textbox", label: "Font") {
                    Picker("", selection: $s.fontFamily) {
                        ForEach(ClockFontFamily.allCases) { f in Text(f.label).tag(f) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                SettingsDivider()
                SettingsRow(icon: "bold", label: "Weight") {
                    Picker("", selection: $s.fontWeight) {
                        ForEach(ClockFontWeight.allCases) { w in Text(w.label).tag(w) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                if s.selectedTheme == .standby {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("StandBy uses Apple-style SF Pro Regular typography.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Font family and weight apply to the other themes.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                SettingsDivider()
                SliderRow(icon: "textformat.size", label: "Font Size",
                          value: $s.fontSize, range: 16...80,
                          display: { "\(Int($0))pt" })
                SettingsDivider()
                DisclosureGroup(isExpanded: $showMoreLook) {
                    VStack(spacing: 0) {
                        SettingsDivider()
                        SliderRow(icon: "arrow.left.and.right.text.vertical", label: "Letter Spacing",
                                  value: $s.letterSpacing, range: -4...20,
                                  display: { "\(Int($0))pt" })
                        SettingsDivider()
                        SliderRow(icon: "circle.lefthalf.filled", label: "Window Opacity",
                                  value: $s.windowOpacity, range: 0.1...1.0,
                                  display: { "\(Int($0 * 100))%" })
                        SettingsDivider()
                        SettingsRow(icon: "bolt.fill", label: "Accent / Glow Color") {
                            ColorPicker("", selection: s.accentColorBinding).labelsHidden().frame(width: 28)
                        }
                        // Custom-theme extras
                        if s.selectedTheme == .custom {
                            SettingsDivider()
                            SettingsRow(icon: "rectangle.fill", label: "Background Color") {
                                ColorPicker("", selection: s.bgColorBinding).labelsHidden().frame(width: 28)
                            }
                            SettingsDivider()
                            SliderRow(icon: "square.fill.on.square", label: "Background Opacity",
                                      value: $s.backgroundOpacity, range: 0.0...1.0,
                                      display: { "\(Int($0 * 100))%" })
                            SettingsDivider()
                            SliderRow(icon: "rectangle.roundedtop", label: "Corner Radius",
                                      value: $s.cornerRadius, range: 0...32,
                                      display: { "\(Int($0))pt" })
                            SettingsDivider()
                            SliderRow(icon: "rectangle.and.pencil.and.ellipsis", label: "Border Opacity",
                                      value: $s.borderOpacity, range: 0.0...1.0,
                                      display: { "\(Int($0 * 100))%" })
                            SettingsDivider()
                            SliderRow(icon: "shadow", label: "Shadow Strength",
                                      value: $s.shadowStrength, range: 0.0...1.0,
                                      display: { "\(Int($0 * 100))%" })
                        }

                        if s.selectedTheme == .transparent || s.selectedTheme == .minimal {
                            SettingsDivider()
                            SliderRow(icon: "square.fill.on.square", label: "Background Opacity",
                                      value: $s.backgroundOpacity, range: 0.0...1.0,
                                      display: { "\(Int($0 * 100))%" })
                        }
                    }
                } label: {
                    Text("More Options").font(.callout)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: Window tab

    private var sizeSection: some View {
        SettingsCard(label: "SIZE & POSITION", icon: "arrow.up.left.and.arrow.down.right") {
            VStack(spacing: 0) {
                // Size buttons
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 20).foregroundStyle(.secondary)
                        Text("Size").font(.callout)
                    }
                    HStack(spacing: 8) {
                        ForEach([SizePreset.small, .medium, .large, .extraLarge], id: \.self) { preset in
                            Button(preset.label) {
                                s.isFullScreen = false
                                s.sizePreset = preset
                            }
                            .buttonStyle(.bordered)
                            .tint(s.sizePreset == preset && !s.isFullScreen ? .accentColor : nil)
                        }
                    }
                }
                .padding(12)

                SettingsDivider()
                // Reset
                HStack {
                    Button {
                        s.isFullScreen = false
                        s.sizePreset = .medium
                        NotificationCenter.default.post(name: .moveToPreset, object: ClockSettings.PositionPreset.reset)
                    } label: {
                        Label("Reset Size & Position", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard(label: "BEHAVIOR", icon: "cursorarrow.rays") {
            VStack(spacing: 0) {
                ToggleRow(icon: "cursorarrow.rays", label: "Click-Through",
                          value: $s.isClickThrough,
                          hint: s.isClickThrough ? LocalizedStringKey("Clicks pass to apps below") : LocalizedStringKey("Drag mode active"))
                SettingsDivider()
                ToggleRow(icon: "eye.trianglebadge.exclamationmark", label: "Adaptive Color",
                          value: $s.adaptiveColor,
                          hint: "Auto-adjust text color to match background")
                    .onChange(of: s.adaptiveColor) { enabled in
                        if enabled { ScreenSampler.requestPermissionIfNeeded() }
                    }
                if s.adaptiveColor { ScreenRecordingWarning() }
                SettingsDivider()
                ToggleRow(icon: "display.2", label: "Show on All Displays",
                          value: $s.mirrorToAllDisplays,
                          hint: "Mirror the clock to every connected monitor")
            }
        }
    }

    private var movementSection: some View {
        SettingsCard(label: "MOVEMENT", icon: "move.3d") {
            VStack(spacing: 0) {
                ToggleRow(icon: "arrow.triangle.2.circlepath", label: "Burn-in Prevention",
                          value: $s.burnInPrevention,
                          hint: "Slowly drifts the clock to protect your display")

                if s.burnInPrevention {
                    SettingsDivider()
                    SliderRow(icon: "clock.arrow.2.circlepath", label: "Drift Interval",
                              value: $s.burnInInterval, range: 30...600,
                              display: { "\(Int($0))s" })
                }

                SettingsDivider()
                ToggleRow(icon: "tv", label: "DVD Bounce",
                          value: $s.dvdBounce,
                          hint: "Clock floats around the screen bouncing off edges")

                if s.dvdBounce {
                    SettingsDivider()
                    SliderRow(icon: "hare", label: "Bounce Speed",
                              value: $s.dvdBounceSpeed, range: 0.5...5.0,
                              display: { String(format: "%.1f", $0) })
                }

            }
        }
    }

    // MARK: General tab

    private var generalSection: some View {
        SettingsCard(label: "GENERAL", icon: "gearshape") {
            ToggleRow(icon: "eye",            label: "Show Overlay",     value: $s.isVisible)
            SettingsDivider()
            ToggleRow(icon: "dock.rectangle", label: "Show in Dock",
                      value: Binding(get: { s.showInDock },
                                     set: { s.showInDock = $0; s.applyDockVisibility($0) }))
            SettingsDivider()
            ToggleRow(icon: "power.circle",   label: "Launch at Login",
                      value: Binding(get: { s.launchAtLogin },
                                     set: { s.launchAtLogin = $0; s.applyLaunchAtLogin($0) }),
                      hint: "Requires app in /Applications folder")
            if !ForkConfig.disablesUpstreamServices {
                SettingsDivider()
                ToggleRow(icon: "arrow.down.circle", label: "Automatically Check for Updates",
                          value: $autoCheckUpdates,
                          hint: "Shows a small pop-up when a new version is available")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        SettingsCard(label: "ABOUT", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Floating Clock Overlay").font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill").foregroundStyle(.blue).font(.title3)
                    Text("Created by **Yousa Bin Sadeque**").font(.callout)
                }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                    Text("Free for personal and educational use.").font(.callout)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.orange).font(.title3)
                    Text("Commercial, business, corporate, resale, SaaS, paid redistribution, internal company use, client work, contract work, monetized use, or use as a feature inside another app/product/service requires prior written permission from Yousa Bin Sadeque.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Divider().padding(.vertical, 2)
                HStack(spacing: 12) {
                    Button {
                        if let url = URL(string: "https://github.com/yousabinsadeque/FloatingClockOverlay/issues") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Feedback", systemImage: "envelope")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: "https://github.com/yousabinsadeque/FloatingClockOverlay") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("GitHub", systemImage: "link")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if ForkConfig.disablesUpstreamServices {
                        Text("Fork build — updates are managed manually.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Button {
                            UpdateChecker.checkForUpdate()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                HStack {
                    Text("Copyright © 2026 Yousa Bin Sadeque. All rights reserved.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("v\(appVersion)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var quitButton: some View {
        Button(role: .destructive) {
            // Goes through AppDelegate.quitApp() so allowQuit is set before terminate
            NotificationCenter.default.post(name: .quitApp, object: nil)
        } label: {
            Label("Quit Floating Clock Overlay", systemImage: "power")
                .frame(maxWidth: .infinity).padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(NSColor.systemRed).opacity(0.85))
        .controlSize(.large)
        .padding(.top, 4).padding(.bottom, 8)
    }
}

// MARK: - Theme Preview Cards

struct ThemeCard: View {
    let theme: ClockTheme
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                preview
                Text("10:10")
                    .font(theme == .standby
                          ? .system(size: 12, weight: .regular, design: .default).monospacedDigit()
                          : .system(size: 11, weight: .light, design: .monospaced))
                    .tracking(theme == .standby ? 0.4 : 0)
                    .foregroundColor(previewTextColor)
                    .shadow(color: neonColor?.opacity(0.8) ?? .clear, radius: 4)
            }
            .frame(width: 76, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.5),
                                  lineWidth: selected ? 2 : 0.5)
            )

            Text(theme.label)
                .font(.caption2)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .weather:
            LinearGradient(colors: [Color(hex: "1a2a4a"), Color(hex: "0d1520")],
                           startPoint: .top, endPoint: .bottom)
        case .transparent:
            ZStack {
                checkerboard
                Color.black.opacity(0.35)
            }
        case .glass:
            // Mini preview of the iOS 26 glass layers
            ZStack {
                checkerboard
                iOSGlassCard(cornerRadius: 8)
            }
        case .standby:
            ZStack {
                LinearGradient(colors: [Color(hex: "09090B"), Color(hex: "030304")],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: "FFB15E").opacity(0.28), .clear],
                               center: .center, startRadius: 0, endRadius: 46)
            }
        case .dark:
            Color(white: 0.08).opacity(0.92)
        case .light:
            Color(white: 0.97).opacity(0.93)
        case .neon:
            Color.black.opacity(0.9)
        case .minimal:
            checkerboard
        case .custom:
            LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .toyStory:
            Color(hex: "1E1031").opacity(0.9)
        case .f1:
            Color(hex: "1A1C20").opacity(0.9)
        case .naruto:
            Color(hex: "0D1117").opacity(0.9)
        case .weatheringYou:
            Color(hex: "161F2E").opacity(0.9)
        case .yourName:
            Color(hex: "161224").opacity(0.9)
        case .frozen:
            Color(hex: "09142B").opacity(0.9)
        case .onePiece:
            Color(hex: "0A192F").opacity(0.9)
        }
    }

    private var previewTextColor: Color {
        switch theme {
        case .weather:        return .white
        case .light:          return Color(white: 0.1)
        case .neon:           return .cyan
        case .standby:        return Color(hex: "FFF6E8")
        case .toyStory:       return Color(hex: "FFD659")
        case .f1:             return Color(hex: "FFCC00")
        case .naruto:         return Color(hex: "F7F7F7")
        case .weatheringYou:  return Color(hex: "FFEA8C")
        case .yourName:       return Color(hex: "E0F7FA")
        case .frozen:         return .white
        case .onePiece:       return Color(hex: "FDE047")
        default:              return .white
        }
    }

    private var neonColor: Color? {
        switch theme {
        case .neon:           return .cyan
        case .standby:        return Color(hex: "FFAE5A")
        case .toyStory:       return Color(hex: "5CF115")
        case .f1:             return Color(hex: "FF3333")
        case .naruto:         return Color(hex: "53A6FD")
        case .weatheringYou:  return Color(hex: "FFB732")
        case .yourName:       return Color(hex: "00E5FF")
        case .frozen:         return Color(hex: "81D4FA")
        case .onePiece:       return Color(hex: "FBBF24")
        default:              return nil
        }
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let sq: CGFloat = 8
            var fill = false
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                fill = Int(y / sq) % 2 == 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: sq, height: sq)),
                             with: .color(fill ? Color(white: 0.6) : Color(white: 0.8)))
                    fill.toggle(); x += sq
                }
                y += sq
            }
        }
    }
}

// MARK: - Reusable Components

struct SettingsCard<Content: View>: View {
    let label: LocalizedStringKey
    let icon:  String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                Text(label).font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 2)

            VStack(spacing: 0) { content() }
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5))
        }
    }
}

struct SettingsRow<Control: View>: View {
    let icon: String; let label: LocalizedStringKey
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            Text(label).font(.callout)
            Spacer()
            control()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

// Adaptive Color only reads the real pixels behind the clock with Screen Recording
// permission. Without it (including after an update re-signs the app) it falls back
// to rough guesses, so say so instead of failing silently.
struct ScreenRecordingWarning: View {
    @State private var granted = ScreenSampler.hasCapturePermission
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        if !granted {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Screen Recording is off, so colors are only approximate.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") { ScreenSampler.openScreenRecordingSettings() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.top, 6)
            HStack {
                Text("Already turned it on? macOS needs a restart to apply it.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Restart Now") { ScreenSampler.relaunch() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
            .onReceive(poll) { _ in granted = ScreenSampler.hasCapturePermission }
        } else {
            Color.clear.frame(height: 0)
                .onReceive(poll) { _ in granted = ScreenSampler.hasCapturePermission }
        }
    }
}

struct QuickToggle: View {
    let icon: String
    let label: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                Text(label).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.25)))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(label))
    }
}

struct ToggleRow: View {
    let icon: String; let label: LocalizedStringKey
    @Binding var value: Bool
    var hint: LocalizedStringKey? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout)
                if let hint { Text(hint).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            Toggle("", isOn: $value).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 12).padding(.vertical, hint != nil ? 8 : 10)
    }
}

struct SliderRow: View {
    let icon: String; let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let display: (Double) -> String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
                Text(label).font(.callout)
                Spacer()
                Text(display(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
            Slider(value: $value, in: range).padding(.leading, 30)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

struct SettingsDivider: View {
    var body: some View { Divider().padding(.leading, 42) }
}
