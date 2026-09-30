import Foundation

/// Where Galley keeps its files.
///
///     <root>/Articles/<uuid>/article.html, meta.json, images/, qr.png
///     <root>/Editions/<uuid>/edition.html, edition.pdf
///     <root>/Support/            bundled scripts and themes, refreshed on launch
public struct GalleyPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Galley`, or `$GALLEY_ROOT` if set.
    public static var `default`: GalleyPaths {
        if let override = ProcessInfo.processInfo.environment["GALLEY_ROOT"], !override.isEmpty {
            return GalleyPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return GalleyPaths(root: support.appendingPathComponent("Galley", isDirectory: true))
    }

    public var articles: URL { root.appendingPathComponent("Articles", isDirectory: true) }
    public var editions: URL { root.appendingPathComponent("Editions", isDirectory: true) }
    public var support: URL { root.appendingPathComponent("Support", isDirectory: true) }

    public func articleFolder(_ id: UUID) -> URL {
        articles.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func editionFolder(_ id: UUID) -> URL {
        editions.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func themeFolder(_ themeID: String) -> URL {
        support.appendingPathComponent("themes/\(themeID)", isDirectory: true)
    }

    public var jsFolder: URL { support.appendingPathComponent("js", isDirectory: true) }

    /// Creates the folders and copies bundled scripts and themes into `Support/`,
    /// so web views that are only allowed to read `root` can load them.
    public func prepare() throws {
        let fm = FileManager.default
        for dir in [articles, editions] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard let bundled = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            throw GalleyError("Galley's bundled resources are missing.")
        }
        if fm.fileExists(atPath: support.path) {
            try fm.removeItem(at: support)
        }
        try fm.copyItem(at: bundled, to: support)
    }

    public func removeArticle(_ id: UUID) {
        try? FileManager.default.removeItem(at: articleFolder(id))
    }
}

enum Resources {
    static func text(_ relativePath: String) throws -> String {
        guard let base = Bundle.module.url(forResource: "Resources", withExtension: nil) else {
            throw GalleyError("Galley's bundled resources are missing.")
        }
        return try String(contentsOf: base.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
