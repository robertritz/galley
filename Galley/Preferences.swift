import Foundation
import GalleyCore

/// Settings keys shared by `@AppStorage` in views and `Library`.
enum Pref {
    static let paper = "paper"
    static let columns = "columns"
    static let masthead = "masthead"
    static let imageMode = "imageMode"
    static let linkNotes = "linkNotes"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            paper: PaperSize.regionDefault.rawValue,
            columns: ColumnLayout.two.rawValue,
            masthead: "Galley",
            imageMode: ImageMode.color.rawValue,
            linkNotes: true,
        ])
    }

    static var renderSettings: RenderSettings {
        let d = UserDefaults.standard
        return RenderSettings(
            paper: PaperSize(rawValue: d.string(forKey: paper) ?? "") ?? .regionDefault,
            columns: ColumnLayout(rawValue: d.integer(forKey: columns)) ?? .two,
            imageMode: ImageMode(rawValue: d.string(forKey: imageMode) ?? "") ?? .color,
            linkNotes: d.bool(forKey: linkNotes)
        )
    }

    /// Changes whenever a setting that affects the layout changes.
    static var renderKey: String {
        let r = renderSettings
        return [r.paper.rawValue, "\(r.columns.rawValue)", r.imageMode.rawValue, "\(r.linkNotes)", mastheadName].joined(separator: "|")
    }

    static var mastheadName: String {
        let name = UserDefaults.standard.string(forKey: masthead)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Galley" : name
    }
}
