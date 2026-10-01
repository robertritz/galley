import AppKit
import Foundation
import Testing
@testable import GalleyCore

struct ExtractionHelperTests {
    @Test func bylinesAreCleaned() {
        #expect(ArticleExtractor.cleanByline("By  Jane   Doe") == "Jane Doe")
        #expect(ArticleExtractor.cleanByline("   ") == nil)
    }

    @Test func publishedDatesParse() {
        #expect(ArticleExtractor.parseDate("2025-05-27T14:02:11.000Z") != nil)
        #expect(ArticleExtractor.parseDate("2025-05-27T14:02:11+08:00") != nil)
        #expect(ArticleExtractor.parseDate("2025-05-27") != nil)
        #expect(ArticleExtractor.parseDate("last Tuesday") == nil)
    }
}

struct CoverPhotoTests {
    @Test func keywordsPreferNamesAndSkipFiller() {
        let k = CoverPhotoFinder.keywords(from: "Mongolia PM expected to call vote of confidence in the face of protests")
        #expect(k.hasPrefix("Mongolia"))
        #expect(!k.contains("expected"))
        #expect(k.split(separator: " ").count <= 3)
    }

    @Test func keywordsHandleCyrillic() {
        let k = CoverPhotoFinder.keywords(from: "Уул уурхайн орлогын хуульчлагдвал Монголоос")
        #expect(!k.isEmpty)
        #expect(k.contains("Монголоос"))
    }

    @Test func emptyTitleGivesNoQuery() {
        #expect(CoverPhotoFinder.keywords(from: "") == "")
    }

    @Test func importedPhotosAreResizedAndSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A 400×300 solid-colour PNG.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 3,
                                   hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let photo = try #require(CoverPhotoFinder.importPhoto(data, into: folder))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(photo.file).path))
        #expect(photo.credit == nil)
    }
}
