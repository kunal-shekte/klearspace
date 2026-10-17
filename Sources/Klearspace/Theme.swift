import AppKit
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Theme {
    // Dynamic NSColors resolve against the window's effective appearance, including
    // SwiftUI overrides. System mode passes nil to preferredColorScheme.
    static func adaptive(_ name: String, light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("Klearspace." + name)) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
    static let accent = adaptive("accent", light: (0.12, 0.43, 0.28), dark: (0.67, 0.91, 0.72))
    static let canvas = adaptive("canvas", light: (0.975, 0.98, 0.97), dark: (0.065, 0.075, 0.073))
    static let panel = adaptive("panel", light: (1, 1, 0.995), dark: (0.10, 0.115, 0.108))
    static let sidebar = adaptive("sidebar", light: (0.94, 0.955, 0.935), dark: (0.052, 0.062, 0.058))
    static let heroEnd = adaptive("heroEnd", light: (0.93, 0.96, 0.925), dark: (0.085, 0.105, 0.091))
    static let muted = adaptive("muted", light: (0.35, 0.40, 0.36), dark: (0.56, 0.61, 0.58))
    static let ink = adaptive("ink", light: (0.10, 0.14, 0.11), dark: (0.91, 0.93, 0.90))
    static let edge = adaptive("edge", light: (0.10, 0.18, 0.12), dark: (1, 1, 1))
    static let warning = adaptive("warning", light: (0.65, 0.31, 0.07), dark: (1, 0.65, 0.27))
    static let blue = adaptive("blue", light: (0.28, 0.39, 0.68), dark: (0.66, 0.74, 0.94))
    static let gold = adaptive("gold", light: (0.56, 0.39, 0.08), dark: (0.90, 0.76, 0.50))
    static let violet = adaptive("violet", light: (0.46, 0.34, 0.64), dark: (0.70, 0.65, 0.85))
    static let coral = adaptive("coral", light: (0.68, 0.30, 0.19), dark: (0.94, 0.64, 0.51))
}
