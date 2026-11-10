import SwiftUI
import Combine
import ServiceManagement

// Single source of truth for all user preferences — persisted to UserDefaults.
final class ClockSettings: ObservableObject {
    static let shared = ClockSettings()

    // MARK: - Overlay Visibility & Behavior
    @Published var isVisible:       Bool
    @Published var showPrimaryPane: Bool
    @Published var showClockCompanion: Bool
    @Published var isClickThrough:  Bool
    @Published var showInDock:      Bool
    @Published var launchAtLogin:   Bool

    // MARK: - Overlay Mode (clock / timer / stopwatch)
    @Published var overlayMode:     OverlayMode

    // MARK: - Theme
    @Published var selectedTheme:   ClockTheme
    @Published var f1Team:          F1Team
    @Published var accentColorR:    Double   // accent / neon glow color
    @Published var accentColorG:    Double
    @Published var accentColorB:    Double
    @Published var bgColorR:        Double   // custom theme background color
    @Published var bgColorG:        Double
    @Published var bgColorB:        Double
    @Published var cornerRadius:    Double
    @Published var borderOpacity:   Double
    @Published var shadowStrength:  Double

    // MARK: - Appearance (shared across themes)
    @Published var windowOpacity:   Double
    @Published var backgroundOpacity: Double
    @Published var textColorRed:    Double
    @Published var textColorGreen:  Double
    @Published var textColorBlue:   Double

    // MARK: - Typography
    @Published var fontFamily:      ClockFontFamily
    @Published var fontWeight:      ClockFontWeight
    @Published var fontSize:        Double
    @Published var letterSpacing:   Double

    // MARK: - Time Format
    @Published var use24Hour:       Bool
    @Published var showSeconds:     Bool
    @Published var showAmPm:        Bool
    @Published var amPmUppercase:   Bool
    @Published var showDayOfWeek:   Bool

    // MARK: - Timer Duration (saved)
    @Published var timerHours:      Int
    @Published var timerMinutes:    Int
    @Published var timerSeconds:    Int

    // MARK: - Window / Size
    @Published var sizePreset:      SizePreset
    @Published var customWidth:     Double
    @Published var customHeight:    Double
    @Published var isFullScreen:    Bool
    @Published var clockAlignment:  ClockAlignment

    // MARK: - Adaptive & Burn-in Prevention
    @Published var adaptiveColor:   Bool
    @Published var burnInPrevention: Bool
    @Published var burnInInterval:  Double   // seconds between drift moves
    @Published var dvdBounce:       Bool
    @Published var dvdBounceSpeed:  Double   // points per tick

    // MARK: - Language
    @Published var clockLanguage:   String   // "" = system default, or locale identifier like "es", "ar"

    // MARK: - Position
    @Published var windowX:         Double
    @Published var windowY:         Double
    @Published var windowScreenOffsetX: Double
    @Published var windowScreenOffsetY: Double
    @Published var windowScreenName:    String
    @Published var mirrorToAllDisplays: Bool

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let d = UserDefaults.standard
        func bool(_ key: String, default def: Bool) -> Bool   { d.object(forKey: key) != nil ? d.bool(forKey: key) : def }
        func dbl(_ key: String, default def: Double) -> Double { d.object(forKey: key) != nil ? d.double(forKey: key) : def }
        func int(_ key: String, default def: Int) -> Int       { d.object(forKey: key) != nil ? d.integer(forKey: key) : def }
        func str(_ key: String) -> String?                     { d.string(forKey: key) }

        isVisible         = bool("isVisible",         default: true)
        showPrimaryPane   = bool("showPrimaryPane",   default: true)
        showClockCompanion = bool("showClockCompanion", default: true)
        isClickThrough    = bool("isClickThrough",    default: true)
        showInDock        = bool("showInDock",        default: true)
        launchAtLogin     = bool("launchAtLogin",     default: false)
        overlayMode       = OverlayMode(rawValue: str("overlayMode") ?? "") ?? .clock
        selectedTheme     = ClockTheme(rawValue: str("selectedTheme") ?? "") ?? .transparent
        f1Team            = F1Team(rawValue: str("f1Team") ?? "") ?? .ferrari
        accentColorR      = dbl("accentColorR",      default: 0.30)
        accentColorG      = dbl("accentColorG",      default: 0.80)
        accentColorB      = dbl("accentColorB",      default: 1.00)
        bgColorR          = dbl("bgColorR",          default: 0.0)
        bgColorG          = dbl("bgColorG",          default: 0.0)
        bgColorB          = dbl("bgColorB",          default: 0.0)
        cornerRadius      = dbl("cornerRadius",      default: 12.0)
        borderOpacity     = dbl("borderOpacity",     default: 0.3)
        shadowStrength    = dbl("shadowStrength",    default: 0.5)
        windowOpacity     = dbl("windowOpacity",     default: 0.85)
        backgroundOpacity = dbl("backgroundOpacity", default: 0.35)
        textColorRed      = dbl("textColorRed",      default: 1.0)
        textColorGreen    = dbl("textColorGreen",    default: 1.0)
        textColorBlue     = dbl("textColorBlue",     default: 1.0)
        fontFamily        = ClockFontFamily(rawValue: str("fontFamily") ?? "") ?? .monospaced
        fontWeight        = ClockFontWeight(rawValue: str("fontWeight") ?? "") ?? .light
        fontSize          = dbl("fontSize",          default: 42.0)
        letterSpacing     = dbl("letterSpacing",     default: 0.0)
        use24Hour         = bool("use24Hour",        default: true)
        // The clock reads better without seconds; timer and stopwatch still
        // always display them.
        showSeconds       = bool("showSeconds",      default: false)
        showAmPm          = bool("showAmPm",         default: true)
        amPmUppercase     = bool("amPmUppercase",    default: true)
        showDayOfWeek     = bool("showDayOfWeek",    default: false)
        timerHours        = int("timerHours",        default: 0)
        timerMinutes      = int("timerMinutes",      default: 5)
        timerSeconds      = int("timerSeconds",      default: 0)
        sizePreset        = SizePreset(rawValue: str("sizePreset") ?? "") ?? .medium
        customWidth       = dbl("customWidth",       default: 260.0)
        customHeight      = dbl("customHeight",      default: 70.0)
        isFullScreen      = bool("isFullScreen",     default: false)
        clockAlignment    = ClockAlignment(rawValue: str("clockAlignment") ?? "") ?? .topRight
        adaptiveColor     = bool("adaptiveColor",    default: false)
        burnInPrevention  = bool("burnInPrevention", default: false)
        burnInInterval    = dbl("burnInInterval",    default: 120.0)
        dvdBounce         = bool("dvdBounce",         default: false)
        dvdBounceSpeed    = dbl("dvdBounceSpeed",    default: 0.7)
        windowX           = dbl("windowX",           default: -1)
        windowY           = dbl("windowY",           default: -1)
        windowScreenOffsetX = dbl("windowScreenOffsetX", default: 0)
        windowScreenOffsetY = dbl("windowScreenOffsetY", default: 0)
        windowScreenName    = str("windowScreenName") ?? ""
        mirrorToAllDisplays = bool("mirrorToAllDisplays", default: false)
        clockLanguage       = str("clockLanguage") ?? ""

        setupPersistence()
    }

    private func setupPersistence() {
        let d = UserDefaults.standard
        $isVisible        .dropFirst().sink { d.set($0, forKey: "isVisible")         }.store(in: &cancellables)
        // Turning the overlay on should never leave the user with zero panes,
        // whichever control path did it (menu, Settings, keyboard shortcut).
        $isVisible        .dropFirst().sink { [weak self] visible in
            guard let self, visible, self.visiblePaneCount == 0 else { return }
            self.showPrimaryPane = true
        }.store(in: &cancellables)
        $showPrimaryPane  .dropFirst().sink { d.set($0, forKey: "showPrimaryPane")   }.store(in: &cancellables)
        $showClockCompanion.dropFirst().sink { d.set($0, forKey: "showClockCompanion") }.store(in: &cancellables)
        $isClickThrough   .dropFirst().sink { d.set($0, forKey: "isClickThrough")    }.store(in: &cancellables)
        $showInDock       .dropFirst().sink { d.set($0, forKey: "showInDock")        }.store(in: &cancellables)
        $launchAtLogin    .dropFirst().sink { d.set($0, forKey: "launchAtLogin")     }.store(in: &cancellables)
        $overlayMode      .dropFirst().sink { d.set($0.rawValue, forKey: "overlayMode")        }.store(in: &cancellables)
        $selectedTheme    .dropFirst().sink { d.set($0.rawValue, forKey: "selectedTheme")      }.store(in: &cancellables)
        $f1Team           .dropFirst().sink { d.set($0.rawValue, forKey: "f1Team")             }.store(in: &cancellables)
        $accentColorR     .dropFirst().sink { d.set($0, forKey: "accentColorR")     }.store(in: &cancellables)
        $accentColorG     .dropFirst().sink { d.set($0, forKey: "accentColorG")     }.store(in: &cancellables)
        $accentColorB     .dropFirst().sink { d.set($0, forKey: "accentColorB")     }.store(in: &cancellables)
        $bgColorR         .dropFirst().sink { d.set($0, forKey: "bgColorR")         }.store(in: &cancellables)
        $bgColorG         .dropFirst().sink { d.set($0, forKey: "bgColorG")         }.store(in: &cancellables)
        $bgColorB         .dropFirst().sink { d.set($0, forKey: "bgColorB")         }.store(in: &cancellables)
        $cornerRadius     .dropFirst().sink { d.set($0, forKey: "cornerRadius")     }.store(in: &cancellables)
        $borderOpacity    .dropFirst().sink { d.set($0, forKey: "borderOpacity")    }.store(in: &cancellables)
        $shadowStrength   .dropFirst().sink { d.set($0, forKey: "shadowStrength")   }.store(in: &cancellables)
        $windowOpacity    .dropFirst().sink { d.set($0, forKey: "windowOpacity")    }.store(in: &cancellables)
        $backgroundOpacity.dropFirst().sink { d.set($0, forKey: "backgroundOpacity")}.store(in: &cancellables)
        $textColorRed     .dropFirst().sink { d.set($0, forKey: "textColorRed")     }.store(in: &cancellables)
        $textColorGreen   .dropFirst().sink { d.set($0, forKey: "textColorGreen")   }.store(in: &cancellables)
        $textColorBlue    .dropFirst().sink { d.set($0, forKey: "textColorBlue")    }.store(in: &cancellables)
        $fontFamily       .dropFirst().sink { d.set($0.rawValue, forKey: "fontFamily")          }.store(in: &cancellables)
        $fontWeight       .dropFirst().sink { d.set($0.rawValue, forKey: "fontWeight")          }.store(in: &cancellables)
        $fontSize         .dropFirst().sink { d.set($0, forKey: "fontSize")         }.store(in: &cancellables)
        $letterSpacing    .dropFirst().sink { d.set($0, forKey: "letterSpacing")    }.store(in: &cancellables)
        $use24Hour        .dropFirst().sink { d.set($0, forKey: "use24Hour")        }.store(in: &cancellables)
        $showSeconds      .dropFirst().sink { d.set($0, forKey: "showSeconds")      }.store(in: &cancellables)
        $showAmPm         .dropFirst().sink { d.set($0, forKey: "showAmPm")         }.store(in: &cancellables)
        $amPmUppercase    .dropFirst().sink { d.set($0, forKey: "amPmUppercase")    }.store(in: &cancellables)
        $showDayOfWeek    .dropFirst().sink { d.set($0, forKey: "showDayOfWeek")    }.store(in: &cancellables)
        $timerHours       .dropFirst().sink { d.set($0, forKey: "timerHours")       }.store(in: &cancellables)
        $timerMinutes     .dropFirst().sink { d.set($0, forKey: "timerMinutes")     }.store(in: &cancellables)
        $timerSeconds     .dropFirst().sink { d.set($0, forKey: "timerSeconds")     }.store(in: &cancellables)
        $sizePreset       .dropFirst().sink { d.set($0.rawValue, forKey: "sizePreset")          }.store(in: &cancellables)
        $customWidth      .dropFirst().sink { d.set($0, forKey: "customWidth")      }.store(in: &cancellables)
        $customHeight     .dropFirst().sink { d.set($0, forKey: "customHeight")     }.store(in: &cancellables)
        $isFullScreen     .dropFirst().sink { d.set($0, forKey: "isFullScreen")     }.store(in: &cancellables)
        $clockAlignment   .dropFirst().sink { d.set($0.rawValue, forKey: "clockAlignment")      }.store(in: &cancellables)
        $adaptiveColor    .dropFirst().sink { d.set($0, forKey: "adaptiveColor")    }.store(in: &cancellables)
        $burnInPrevention .dropFirst().sink { d.set($0, forKey: "burnInPrevention") }.store(in: &cancellables)
        $burnInInterval   .dropFirst().sink { d.set($0, forKey: "burnInInterval")   }.store(in: &cancellables)
        $dvdBounce        .dropFirst().sink { d.set($0, forKey: "dvdBounce")        }.store(in: &cancellables)
        $dvdBounceSpeed   .dropFirst().sink { d.set($0, forKey: "dvdBounceSpeed")   }.store(in: &cancellables)
        $windowX          .dropFirst().sink { d.set($0, forKey: "windowX")          }.store(in: &cancellables)
        $windowY          .dropFirst().sink { d.set($0, forKey: "windowY")          }.store(in: &cancellables)
        $windowScreenOffsetX .dropFirst().sink { d.set($0, forKey: "windowScreenOffsetX") }.store(in: &cancellables)
        $windowScreenOffsetY .dropFirst().sink { d.set($0, forKey: "windowScreenOffsetY") }.store(in: &cancellables)
        $windowScreenName    .dropFirst().sink { d.set($0, forKey: "windowScreenName")    }.store(in: &cancellables)
        $mirrorToAllDisplays .dropFirst().sink { d.set($0, forKey: "mirrorToAllDisplays") }.store(in: &cancellables)
        $clockLanguage       .dropFirst().sink { d.set($0, forKey: "clockLanguage")      }.store(in: &cancellables)
    }

    // MARK: - Computed Color Helpers

    var textColor: Color   { Color(red: textColorRed,  green: textColorGreen,  blue: textColorBlue) }
    var accentColor: Color { Color(red: accentColorR,  green: accentColorG,    blue: accentColorB)  }
    var bgColor: Color     { Color(red: bgColorR,      green: bgColorG,        blue: bgColorB)      }

    var textColorBinding: Binding<Color> {
        Binding(get: { self.textColor }, set: { self.applyTextColor($0) })
    }
    var accentColorBinding: Binding<Color> {
        Binding(get: { self.accentColor }, set: { self.applyAccentColor($0) })
    }
    var bgColorBinding: Binding<Color> {
        Binding(get: { self.bgColor }, set: { self.applyBgColor($0) })
    }

    func applyTextColor(_ c: Color) {
        guard let rgb = NSColor(c).usingColorSpace(.sRGB) else { return }
        textColorRed = rgb.redComponent; textColorGreen = rgb.greenComponent; textColorBlue = rgb.blueComponent
    }
    func applyAccentColor(_ c: Color) {
        guard let rgb = NSColor(c).usingColorSpace(.sRGB) else { return }
        accentColorR = rgb.redComponent; accentColorG = rgb.greenComponent; accentColorB = rgb.blueComponent
    }
    func applyBgColor(_ c: Color) {
        guard let rgb = NSColor(c).usingColorSpace(.sRGB) else { return }
        bgColorR = rgb.redComponent; bgColorG = rgb.greenComponent; bgColorB = rgb.blueComponent
    }

    // MARK: - System Helpers

    func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    func applyDockVisibility(_ show: Bool) {
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    var isClockCompanionVisible: Bool {
        overlayMode != .clock && showClockCompanion
    }

    var visiblePaneCount: Int {
        (showPrimaryPane ? 1 : 0) + (isClockCompanionVisible ? 1 : 0)
    }

    // MARK: - Position Presets (used by ClockWindowController)

    enum PositionPreset { case topLeft, topRight, bottomLeft, bottomRight, center, reset }
}

extension Notification.Name {
    static let moveToPreset    = Notification.Name("FloatingClock.moveToPreset")
    static let applySizePreset = Notification.Name("FloatingClock.applySizePreset")
    static let quitApp         = Notification.Name("FloatingClock.quitApp")
    static let openSettings    = Notification.Name("FloatingClock.openSettings")
}
