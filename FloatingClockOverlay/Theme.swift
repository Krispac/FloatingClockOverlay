import SwiftUI
import AppKit

// MARK: - Clock Theme

enum ClockTheme: String, CaseIterable, Identifiable {
    case transparent    = "transparent"
    case glass          = "glass"
    case standby        = "standby"
    case dark           = "dark"
    case light          = "light"
    case neon           = "neon"
    case minimal        = "minimal"
    case custom         = "custom"
    // Special
    case weather        = "weather"
    // Pop culture
    case toyStory       = "toyStory"
    case f1             = "f1"
    case naruto         = "naruto"
    case weatheringYou  = "weatheringYou"
    case yourName       = "yourName"
    case frozen         = "frozen"
    case onePiece       = "onePiece"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .weather:       return "Weather"
        case .transparent:   return "Transparent"
        case .glass:         return "Glass"
        case .standby:       return "StandBy"
        case .dark:          return "Dark"
        case .light:         return "Light"
        case .neon:          return "Neon"
        case .minimal:       return "Minimal"
        case .custom:        return "Custom"
        case .toyStory:      return "Toy Story"
        case .f1:            return "F1"
        case .naruto:        return "Naruto"
        case .weatheringYou: return "Weathering"
        case .yourName:      return "Your Name"
        case .frozen:        return "Frozen"
        case .onePiece:      return "One Piece"
        }
    }
    var icon: String {
        switch self {
        case .weather:       return "cloud.sun.fill"
        case .transparent:   return "circle.dashed"
        case .glass:         return "circle.hexagongrid"
        case .standby:       return "moon.stars.fill"
        case .dark:          return "moon.fill"
        case .light:         return "sun.max.fill"
        case .neon:          return "bolt.fill"
        case .minimal:       return "minus.circle"
        case .custom:        return "slider.horizontal.3"
        case .toyStory:      return "star.fill"
        case .f1:            return "flag.checkered"
        case .naruto:        return "flame.fill"
        case .weatheringYou: return "cloud.rain.fill"
        case .yourName:      return "sparkles"
        case .frozen:        return "snowflake"
        case .onePiece:      return "leaf.fill"
        }
    }

    var isPopCulture: Bool {
        switch self {
        case .toyStory, .f1, .naruto, .weatheringYou, .yourName, .frozen, .onePiece:
            return true
        default:
            return false
        }
    }

    var isAnimated: Bool { isPopCulture || self == .weather }
}

// MARK: - F1 Team

enum F1Team: String, CaseIterable, Identifiable {
    case redBull     = "redBull"
    case ferrari     = "ferrari"
    case mercedes    = "mercedes"
    case mcLaren     = "mcLaren"
    case astonMartin = "astonMartin"
    case alpine      = "alpine"
    case williams    = "williams"
    case rb          = "rb"
    case cadillac    = "cadillac"
    case stake       = "stake"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .redBull:     return "Red Bull"
        case .ferrari:     return "Ferrari"
        case .mercedes:    return "Mercedes"
        case .mcLaren:     return "McLaren"
        case .astonMartin: return "Aston Martin"
        case .alpine:      return "Alpine"
        case .williams:    return "Williams"
        case .rb:          return "RB"
        case .cadillac:    return "Cadillac"
        case .stake:       return "Stake"
        }
    }

    var carColor: Color {
        switch self {
        case .redBull:     return Color(hex: "1B2A4A")
        case .ferrari:     return Color(hex: "E8002D")
        case .mercedes:    return Color(hex: "27F4D2")
        case .mcLaren:     return Color(hex: "FF8000")
        case .astonMartin: return Color(hex: "229971")
        case .alpine:      return Color(hex: "FF87BC")
        case .williams:    return Color(hex: "64C4FF")
        case .rb:          return Color(hex: "6692FF")
        case .cadillac:    return Color(hex: "1E1E1E")
        case .stake:       return Color(hex: "00E701")
        }
    }

    var accentColor: Color {
        switch self {
        case .redBull:     return Color(hex: "FFD700")
        case .ferrari:     return Color(hex: "FFCC00")
        case .mercedes:    return Color(hex: "00A19C")
        case .mcLaren:     return Color(hex: "FFD700")
        case .astonMartin: return Color(hex: "CEDC00")
        case .alpine:      return Color(hex: "0093CC")
        case .williams:    return Color(hex: "FFFFFF")
        case .rb:          return Color(hex: "FF3333")
        case .cadillac:    return Color(hex: "C0A44D")
        case .stake:       return Color(hex: "00E701")
        }
    }

    var number: String {
        switch self {
        case .redBull:     return "1"
        case .ferrari:     return "16"
        case .mercedes:    return "44"
        case .mcLaren:     return "4"
        case .astonMartin: return "14"
        case .alpine:      return "10"
        case .williams:    return "23"
        case .rb:          return "22"
        case .cadillac:    return "2"
        case .stake:       return "27"
        }
    }
}

// MARK: - Theme Style

struct ThemeStyle {
    var useVibrancy:    Bool
    var useGlass:       Bool       // true = render iOSGlassCard instead of flat color
    var bgColor:        Color
    var bgOpacity:      Double
    var textColor:      Color
    var cornerRadius:   Double
    var borderColor:    Color
    var borderOpacity:  Double
    var shadowOpacity:  Double
    var useNeonGlow:    Bool
    var glowColor:      Color
}

extension ClockTheme {
    func resolved(using s: ClockSettings) -> ThemeStyle {
        let cr = s.cornerRadius

        switch self {
        case .transparent:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: .black, bgOpacity: s.backgroundOpacity,
                              textColor: s.textColor, cornerRadius: cr,
                              borderColor: .white, borderOpacity: 0,
                              shadowOpacity: s.shadowStrength,
                              useNeonGlow: false, glowColor: .clear)

        case .glass:
            return ThemeStyle(useVibrancy: true, useGlass: true,
                              bgColor: .clear, bgOpacity: 0,
                              textColor: s.textColor, cornerRadius: cr,
                              borderColor: .white, borderOpacity: 0,
                              shadowOpacity: 0.25,
                              useNeonGlow: false, glowColor: .clear)

        case .standby:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "050506"), bgOpacity: 0.96,
                              textColor: Color(hex: "FFF6E8"), cornerRadius: cr,
                              borderColor: Color(hex: "FFD7A1"), borderOpacity: 0.08,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "FFAE5A"))

        case .dark:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(white: 0.08), bgOpacity: 0.92,
                              textColor: s.textColor, cornerRadius: cr,
                              borderColor: .white, borderOpacity: 0.12,
                              shadowOpacity: 0.7,
                              useNeonGlow: false, glowColor: .clear)

        case .light:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(white: 0.97), bgOpacity: 0.93,
                              textColor: s.textColor, cornerRadius: cr,
                              borderColor: Color(white: 0.5), borderOpacity: 0.12,
                              shadowOpacity: 0.15,
                              useNeonGlow: false, glowColor: .clear)

        case .neon:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(white: 0.03), bgOpacity: 0.90,
                              textColor: s.accentColor, cornerRadius: cr,
                              borderColor: s.accentColor, borderOpacity: 0.8,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: s.accentColor)

        case .minimal:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: .clear, bgOpacity: 0,
                              textColor: s.textColor, cornerRadius: 0,
                              borderColor: .clear, borderOpacity: 0,
                              shadowOpacity: s.shadowStrength,
                              useNeonGlow: false, glowColor: .clear)

        case .custom:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: s.bgColor, bgOpacity: s.backgroundOpacity,
                              textColor: s.textColor, cornerRadius: cr,
                              borderColor: s.accentColor, borderOpacity: s.borderOpacity,
                              shadowOpacity: s.shadowStrength,
                              useNeonGlow: false, glowColor: .clear)

        case .weather:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: .clear, bgOpacity: 0,
                              textColor: s.textColor, cornerRadius: 0,
                              borderColor: .clear, borderOpacity: 0,
                              shadowOpacity: 0.6,
                              useNeonGlow: false, glowColor: .clear)

        // ── Pop Culture Themes ──────────────────────────────────

        case .toyStory:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "1E1031"), bgOpacity: 0.90,
                              textColor: Color(hex: "FFD659"), cornerRadius: cr,
                              borderColor: Color(hex: "72E327"), borderOpacity: 0.6,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "5CF115"))

        case .f1:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "1A1C20"), bgOpacity: 0.90,
                              textColor: Color(hex: "FFCC00"), cornerRadius: cr,
                              borderColor: Color(hex: "E10600"), borderOpacity: 0.7,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "FF3333"))

        case .naruto:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "0D1117"), bgOpacity: 0.90,
                              textColor: Color(hex: "F7F7F7"), cornerRadius: cr,
                              borderColor: Color(hex: "FF7B00"), borderOpacity: 0.7,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "53A6FD"))

        case .weatheringYou:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "161F2E"), bgOpacity: 0.90,
                              textColor: Color(hex: "FFEA8C"), cornerRadius: cr,
                              borderColor: Color(hex: "4BA3E3"), borderOpacity: 0.6,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "FFB732"))

        case .yourName:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "161224"), bgOpacity: 0.90,
                              textColor: Color(hex: "E0F7FA"), cornerRadius: cr,
                              borderColor: Color(hex: "FF4D85"), borderOpacity: 0.6,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "00E5FF"))

        case .frozen:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "09142B"), bgOpacity: 0.90,
                              textColor: .white, cornerRadius: cr,
                              borderColor: Color(hex: "4DD0E1"), borderOpacity: 0.6,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "81D4FA"))

        case .onePiece:
            return ThemeStyle(useVibrancy: false, useGlass: false,
                              bgColor: Color(hex: "0A192F"), bgOpacity: 0.90,
                              textColor: Color(hex: "FDE047"), cornerRadius: cr,
                              borderColor: Color(hex: "DC2626"), borderOpacity: 0.7,
                              shadowOpacity: 0,
                              useNeonGlow: true, glowColor: Color(hex: "FBBF24"))
        }
    }
}

// MARK: - StandBy Night Background
//
// A near-black pane with a warm ambient glow behind the digits, a soft top
// specular edge and no heavy border. Inspired by iPhone StandBy at night.

struct StandByBackground: View {
    var cornerRadius: Double
    var paneCount: Int = 1

    var body: some View {
        let cr = max(8, cornerRadius)
        let count = max(1, paneCount)

        ZStack {
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(hex: "09090B"), location: 0.0),
                            .init(color: Color(hex: "030304"), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.96)

            ForEach(0..<count, id: \.self) { index in
                RadialGradient(
                    colors: [
                        Color(hex: "FFB15E").opacity(count == 1 ? 0.20 : 0.17),
                        Color(hex: "FFB15E").opacity(count == 1 ? 0.05 : 0.04),
                        .clear,
                    ],
                    center: UnitPoint(x: (Double(index) + 0.5) / Double(count), y: 0.5),
                    startRadius: 0,
                    endRadius: count == 1 ? 150 : 130
                )
                .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
            }

            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.12), location: 0.0),
                            .init(color: Color.white.opacity(0.04), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
    }
}

// MARK: - iOS 26 Liquid Glass Card
//
// Replicates the layered glass material from iOS 26 / macOS 27:
//
//  Layer 1 – Ultra-thin blur of the desktop behind the window
//  Layer 2 – Subtle color-matched tint that picks up the wallpaper
//  Layer 3 – Top specular glare (bright edge catch)
//  Layer 4 – Inner rim highlight
//  Layer 5 – Outer hairline border with gradient
//
// The result is a transparent, frosted pane that blends with any wallpaper.

struct iOSGlassCard: View {
    var cornerRadius: Double

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        let cr = max(8, cornerRadius)

        ZStack {
            // ── 1. Ultra-thin real blur — lets the wallpaper show through ────
            VisualEffectBackground(material: .underPageBackground, blending: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))

            // ── 2. Very subtle tint — almost invisible, just adds body ───────
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.08 : 0.15), location: 0.0),
                            .init(color: Color.white.opacity(isDark ? 0.02 : 0.05), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // ── 3. Top specular glare — soft light catch at the top edge ─────
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.20 : 0.35), location: 0.00),
                            .init(color: Color.white.opacity(isDark ? 0.06 : 0.12), location: 0.25),
                            .init(color: Color.clear,                               location: 0.50),
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: cr, style: .continuous))
                .padding(.horizontal, 1)
                .padding(.top, 1)

            // ── 4. Inner rim — subtle highlight just inside the edge ─────────
            RoundedRectangle(cornerRadius: cr - 0.5, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.30 : 0.50), location: 0.0),
                            .init(color: Color.white.opacity(isDark ? 0.05 : 0.10), location: 0.4),
                            .init(color: Color.white.opacity(0.02),                 location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    ),
                    lineWidth: 1.0
                )
                .padding(0.5)

            // ── 5. Outer hairline border — gradient: bright top, subtle bottom
            RoundedRectangle(cornerRadius: cr, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(isDark ? 0.18 : 0.30), location: 0.0),
                            .init(color: Color.white.opacity(isDark ? 0.06 : 0.10), location: 0.5),
                            .init(color: Color.white.opacity(0.03),                 location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint:   .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blending
        v.state        = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blending
    }
}

// MARK: - Font Family

enum ClockFontFamily: String, CaseIterable, Identifiable {
    case system     = "system"
    case rounded    = "rounded"
    case monospaced = "monospaced"
    case serif      = "serif"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var design: Font.Design {
        switch self {
        case .system:     return .default
        case .rounded:    return .rounded
        case .monospaced: return .monospaced
        case .serif:      return .serif
        }
    }
}

// MARK: - Font Weight

enum ClockFontWeight: String, CaseIterable, Identifiable {
    case thin     = "thin"
    case light    = "light"
    case regular  = "regular"
    case medium   = "medium"
    case semibold = "semibold"
    case bold     = "bold"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var weight: Font.Weight {
        switch self {
        case .thin:     return .thin
        case .light:    return .light
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        }
    }
}

// MARK: - Size Preset

enum SizePreset: String, CaseIterable, Identifiable {
    case small      = "small"
    case medium     = "medium"
    case large      = "large"
    case extraLarge = "extraLarge"
    case fullScreen = "fullScreen"
    case custom     = "custom"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .small:      return NSLocalizedString("Small", comment: "")
        case .medium:     return NSLocalizedString("Medium", comment: "")
        case .large:      return NSLocalizedString("Large", comment: "")
        case .extraLarge: return NSLocalizedString("Extra Large", comment: "")
        case .fullScreen: return NSLocalizedString("Full Screen", comment: "")
        case .custom:     return NSLocalizedString("Custom", comment: "")
        }
    }
    var contentSize: NSSize? {
        switch self {
        case .small:      return NSSize(width: 160, height: 50)
        case .medium:     return NSSize(width: 260, height: 70)
        case .large:      return NSSize(width: 380, height: 90)
        case .extraLarge: return NSSize(width: 520, height: 120)
        default:          return nil
        }
    }
}

// MARK: - Clock Alignment

enum ClockAlignment: String, CaseIterable, Identifiable {
    case topLeft      = "topLeft"
    case topCenter    = "topCenter"
    case topRight     = "topRight"
    case centerLeft   = "centerLeft"
    case center       = "center"
    case centerRight  = "centerRight"
    case bottomLeft   = "bottomLeft"
    case bottomCenter = "bottomCenter"
    case bottomRight  = "bottomRight"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .topLeft:      return "arrow.up.left"
        case .topCenter:    return "arrow.up"
        case .topRight:     return "arrow.up.right"
        case .centerLeft:   return "arrow.left"
        case .center:       return "dot.scope"
        case .centerRight:  return "arrow.right"
        case .bottomLeft:   return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight:  return "arrow.down.right"
        }
    }
    var swiftUIAlignment: Alignment {
        switch self {
        case .topLeft:      return .topLeading
        case .topCenter:    return .top
        case .topRight:     return .topTrailing
        case .centerLeft:   return .leading
        case .center:       return .center
        case .centerRight:  return .trailing
        case .bottomLeft:   return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight:  return .bottomTrailing
        }
    }
}

// MARK: - Hex Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
