import AppKit
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        }
    }

    static var current: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return AppLanguage(rawValue: raw) ?? .english
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case automatic

    var id: String { rawValue }

    var title: String {
        title(in: .current)
    }

    func title(in language: AppLanguage) -> String {
        switch (self, language) {
        case (.dark, .english): "Dark"
        case (.dark, .chinese): "暗色"
        case (.light, .english): "Light"
        case (.light, .chinese): "亮色"
        case (.automatic, .english): "Auto"
        case (.automatic, .chinese): "自动"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .automatic: nil
        }
    }

    var appKitAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .automatic: nil
        }
    }
}
