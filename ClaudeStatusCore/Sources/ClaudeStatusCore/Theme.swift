import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Color hex helpers

public extension Color {
    init(hexOrFallback hex: String?, fallback: Color) {
        guard let raw = hex?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: ""),
              raw.count >= 6 else {
            self = fallback
            return
        }
        let scanner = Scanner(string: String(raw.prefix(6)))
        var value: UInt64 = 0
        guard scanner.scanHexInt64(&value) else {
            self = fallback
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        #elseif canImport(UIKit)
        var rF: CGFloat = 0, gF: CGFloat = 0, bF: CGFloat = 0, aF: CGFloat = 0
        UIColor(self).getRed(&rF, green: &gF, blue: &bF, alpha: &aF)
        let r = Int(round(rF * 255))
        let g = Int(round(gF * 255))
        let b = Int(round(bF * 255))
        return String(format: "#%02X%02X%02X",
                      max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
        #else
        return "#000000"
        #endif
    }

    /// Smooth green->yellow->orange->red gradient stops.
    static var usageGradientStops: [Gradient.Stop] {
        [
            .init(color: Color(red: 0.40, green: 0.85, blue: 0.55), location: 0.00),
            .init(color: Color(red: 0.85, green: 0.90, blue: 0.30), location: 0.45),
            .init(color: Color(red: 1.00, green: 0.65, blue: 0.20), location: 0.75),
            .init(color: Color(red: 0.95, green: 0.30, blue: 0.30), location: 1.00),
        ]
    }

    /// Stepped colors mirroring Claude.ai usage indicators.
    /// 0-50 blue, 50-70 yellow, 70-90 orange, 90-100 red.
    static var usageSteppedStops: [Gradient.Stop] {
        let blue   = Color(red: 0.30, green: 0.55, blue: 0.90)
        let yellow = Color(red: 0.95, green: 0.78, blue: 0.10)
        let orange = Color(red: 0.97, green: 0.55, blue: 0.10)
        let red    = Color(red: 0.92, green: 0.27, blue: 0.27)
        return [
            .init(color: blue,   location: 0.00),
            .init(color: blue,   location: 0.50),
            .init(color: yellow, location: 0.50),
            .init(color: yellow, location: 0.70),
            .init(color: orange, location: 0.70),
            .init(color: orange, location: 0.90),
            .init(color: red,    location: 0.90),
            .init(color: red,    location: 1.00),
        ]
    }

    /// Single color sampled from the smooth gradient at a utilization percentage (0-100).
    static func usageGradient(at utilization: Double) -> Color {
        let frac = min(max(utilization / 100.0, 0), 1)
        let stops: [(Double, Double, Double, Double)] = [
            (0.00, 0.40, 0.85, 0.55),
            (0.45, 0.85, 0.90, 0.30),
            (0.75, 1.00, 0.65, 0.20),
            (1.00, 0.95, 0.30, 0.30),
        ]
        for i in 0..<(stops.count - 1) {
            let (loP, loR, loG, loB) = stops[i]
            let (hiP, hiR, hiG, hiB) = stops[i + 1]
            if frac >= loP && frac <= hiP {
                let t = hiP == loP ? 0 : (frac - loP) / (hiP - loP)
                return Color(
                    red:   loR + (hiR - loR) * t,
                    green: loG + (hiG - loG) * t,
                    blue:  loB + (hiB - loB) * t
                )
            }
        }
        return Color(red: stops.last!.1, green: stops.last!.2, blue: stops.last!.3)
    }

    /// Single color from the stepped Claude-style scale at a utilization (0-100).
    static func usageStepped(at utilization: Double) -> Color {
        let u = max(0, utilization)
        if u < 50 { return Color(red: 0.30, green: 0.55, blue: 0.90) }
        if u < 70 { return Color(red: 0.95, green: 0.78, blue: 0.10) }
        if u < 90 { return Color(red: 0.97, green: 0.55, blue: 0.10) }
        return        Color(red: 0.92, green: 0.27, blue: 0.27)
    }
}

// MARK: - ColorMode

public enum ColorMode: String, CaseIterable, Identifiable, Sendable {
    case solid
    case gradient
    case stepped

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .solid:    return "Solid"
        case .gradient: return "Gradient"
        case .stepped:  return "Stepped"
        }
    }
}

// MARK: - BackgroundMode

public enum BackgroundMode: String, CaseIterable, Identifiable, Sendable {
    case solid
    case fadeFromLight
    case fadeFromDark

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .solid:         return "Solid"
        case .fadeFromLight: return "Light gradient"
        case .fadeFromDark:  return "Dark gradient"
        }
    }
}

// MARK: - Theme storage

public enum ThemeKeys {
    public static let backgroundHex      = "themeBackgroundHex"
    public static let backgroundMode     = "themeBackgroundMode"
    public static let accentHex          = "themeAccentHex"
    public static let barHex             = "themeBarHex"
    public static let accentMode         = "themeAccentMode"
    public static let barMode            = "themeBarMode"
    // Legacy (kept for migration only):
    public static let accentUseGradient  = "themeAccentUseGradient"
}

public enum ThemeDefaults {
    public static let backgroundHex      = "#000000"
    public static let backgroundMode     = BackgroundMode.solid
    public static let accentHex          = "#FF9500"
    public static let barHex             = ""
    public static let accentMode         = ColorMode.solid
    public static let barMode            = ColorMode.gradient
    public static let backgroundColor    = Color.black
    public static let accentColor        = Color.orange
}

@MainActor
public final class ThemeStore: ObservableObject {
    public static let shared = ThemeStore()

    @Published public var backgroundHex: String { didSet { Self.write(backgroundHex, key: ThemeKeys.backgroundHex) } }
    @Published public var backgroundMode: BackgroundMode { didSet { Self.write(backgroundMode.rawValue, key: ThemeKeys.backgroundMode) } }
    @Published public var accentHex:     String { didSet { Self.write(accentHex,     key: ThemeKeys.accentHex) } }
    @Published public var barHex:        String { didSet { Self.write(barHex,        key: ThemeKeys.barHex) } }
    @Published public var accentMode:    ColorMode { didSet { Self.write(accentMode.rawValue, key: ThemeKeys.accentMode) } }
    @Published public var barMode:       ColorMode { didSet { Self.write(barMode.rawValue,    key: ThemeKeys.barMode) } }

    public init() {
        let d = SharedCache.defaults
        self.backgroundHex = d.string(forKey: ThemeKeys.backgroundHex) ?? ThemeDefaults.backgroundHex
        if let raw = d.string(forKey: ThemeKeys.backgroundMode), let m = BackgroundMode(rawValue: raw) {
            self.backgroundMode = m
        } else {
            self.backgroundMode = ThemeDefaults.backgroundMode
        }
        self.accentHex     = d.string(forKey: ThemeKeys.accentHex)     ?? ThemeDefaults.accentHex
        self.barHex        = d.string(forKey: ThemeKeys.barHex)        ?? ThemeDefaults.barHex

        // accentMode: prefer explicit key, else migrate from legacy bool
        if let raw = d.string(forKey: ThemeKeys.accentMode), let m = ColorMode(rawValue: raw) {
            self.accentMode = m
        } else if (d.object(forKey: ThemeKeys.accentUseGradient) as? Bool) == true {
            self.accentMode = .gradient
        } else {
            self.accentMode = ThemeDefaults.accentMode
        }

        // barMode: prefer explicit key, else migrate from old empty-hex-as-gradient pattern
        let storedBarHex = d.string(forKey: ThemeKeys.barHex) ?? ThemeDefaults.barHex
        if let raw = d.string(forKey: ThemeKeys.barMode), let m = ColorMode(rawValue: raw) {
            self.barMode = m
        } else {
            self.barMode = storedBarHex.isEmpty ? .gradient : .solid
        }
    }

    public var background: Color { Color(hexOrFallback: backgroundHex, fallback: ThemeDefaults.backgroundColor) }
    public var accent:     Color { Color(hexOrFallback: accentHex,     fallback: ThemeDefaults.accentColor) }

    public func accentColor(forUtilization u: Double?) -> Color {
        switch accentMode {
        case .solid:    return accent
        case .gradient: return u.map(Color.usageGradient(at:)) ?? accent
        case .stepped:  return u.map(Color.usageStepped(at:))  ?? accent
        }
    }

    public var barSolidColor: Color {
        Color(hexOrFallback: barHex, fallback: ThemeDefaults.accentColor)
    }


    public var backgroundStyle: AnyShapeStyle {
        let c = background
        switch backgroundMode {
        case .solid:
            return AnyShapeStyle(c)
        case .fadeFromLight:
            return AnyShapeStyle(LinearGradient(colors: [Color.white, c], startPoint: .top, endPoint: .bottom))
        case .fadeFromDark:
            return AnyShapeStyle(LinearGradient(colors: [Color.black, c], startPoint: .top, endPoint: .bottom))
        }
    }

    public static func readBackgroundStyle() -> AnyShapeStyle {
        let raw = SharedCache.defaults.string(forKey: ThemeKeys.backgroundMode) ?? ThemeDefaults.backgroundMode.rawValue
        let mode = BackgroundMode(rawValue: raw) ?? ThemeDefaults.backgroundMode
        let c = readBackground()
        switch mode {
        case .solid:
            return AnyShapeStyle(c)
        case .fadeFromLight:
            return AnyShapeStyle(LinearGradient(colors: [Color.white, c], startPoint: .top, endPoint: .bottom))
        case .fadeFromDark:
            return AnyShapeStyle(LinearGradient(colors: [Color.black, c], startPoint: .top, endPoint: .bottom))
        }
    }
    public func resetToDefaults() {
        backgroundHex = ThemeDefaults.backgroundHex
        accentHex     = ThemeDefaults.accentHex
        barHex        = ThemeDefaults.barHex
        accentMode    = ThemeDefaults.accentMode
        barMode       = ThemeDefaults.barMode
    }

    private static func write(_ value: String, key: String) {
        SharedCache.defaults.set(value, forKey: key)
    }

    // Static reads for the widget extension
    public static func readBackground() -> Color {
        let hex = SharedCache.defaults.string(forKey: ThemeKeys.backgroundHex) ?? ThemeDefaults.backgroundHex
        return Color(hexOrFallback: hex, fallback: ThemeDefaults.backgroundColor)
    }
    public static func readAccent() -> Color {
        let hex = SharedCache.defaults.string(forKey: ThemeKeys.accentHex) ?? ThemeDefaults.accentHex
        return Color(hexOrFallback: hex, fallback: ThemeDefaults.accentColor)
    }
    public static func readAccentMode() -> ColorMode {
        if let raw = SharedCache.defaults.string(forKey: ThemeKeys.accentMode), let m = ColorMode(rawValue: raw) { return m }
        if (SharedCache.defaults.object(forKey: ThemeKeys.accentUseGradient) as? Bool) == true { return .gradient }
        return ThemeDefaults.accentMode
    }
    public static func readBarMode() -> ColorMode {
        if let raw = SharedCache.defaults.string(forKey: ThemeKeys.barMode), let m = ColorMode(rawValue: raw) { return m }
        let hex = SharedCache.defaults.string(forKey: ThemeKeys.barHex) ?? ""
        return hex.isEmpty ? .gradient : .solid
    }
    public static func readAccentColor(forUtilization u: Double?) -> Color {
        switch readAccentMode() {
        case .solid:    return readAccent()
        case .gradient: return u.map(Color.usageGradient(at:)) ?? readAccent()
        case .stepped:  return u.map(Color.usageStepped(at:))  ?? readAccent()
        }
    }
    public static func readBarSolidColor() -> Color {
        let hex = SharedCache.defaults.string(forKey: ThemeKeys.barHex) ?? ""
        return Color(hexOrFallback: hex, fallback: ThemeDefaults.accentColor)
    }
}
