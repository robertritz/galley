import Foundation
import GalleyCore

/// Settings keys shared by `@AppStorage` in views and `Library`.
enum Pref {
    static let paper = "paper"
    static let cadenceKind = "cadence.kind"
    static let cadenceWeekday = "cadence.weekday"
    static let cadenceMonthDay = "cadence.monthDay"
    static let masthead = "masthead"
    static let imageMode = "imageMode"
    static let linkNotes = "linkNotes"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            paper: PaperSize.regionDefault.rawValue,
            cadenceKind: Cadence.Kind.weekly.rawValue,
            cadenceWeekday: 1,
            cadenceMonthDay: 1,
            masthead: "Galley",
            imageMode: ImageMode.color.rawValue,
            linkNotes: true,
        ])
    }

    static var cadence: Cadence {
        let d = UserDefaults.standard
        return Cadence(
            kind: Cadence.Kind(rawValue: d.string(forKey: cadenceKind) ?? "") ?? .weekly,
            weekday: d.integer(forKey: cadenceWeekday),
            monthDay: d.integer(forKey: cadenceMonthDay)
        )
    }

    static var renderSettings: RenderSettings {
        let d = UserDefaults.standard
        return RenderSettings(
            paper: PaperSize(rawValue: d.string(forKey: paper) ?? "") ?? .regionDefault,
            imageMode: ImageMode(rawValue: d.string(forKey: imageMode) ?? "") ?? .color,
            linkNotes: d.bool(forKey: linkNotes)
        )
    }

    /// Changes whenever a setting that affects the layout changes.
    static var renderKey: String {
        let r = renderSettings
        return [r.paper.rawValue, r.imageMode.rawValue, "\(r.linkNotes)", mastheadName, "\(cadence)"].joined(separator: "|")
    }

    static var mastheadName: String {
        let name = UserDefaults.standard.string(forKey: masthead)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Galley" : name
    }
}
