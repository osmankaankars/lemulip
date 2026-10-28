import XCTest
@testable import LemulipCore

final class InterfacePolicyTests: XCTestCase {
    func testCompletionPreferencePreservesLegacyFinderChoice() {
        XCTAssertEqual(CompletionPresentation.resolve(stored: nil, legacyReveal: true), .finder)
        XCTAssertEqual(CompletionPresentation.resolve(stored: nil, legacyReveal: false), .quiet)
        XCTAssertEqual(CompletionPresentation.resolve(stored: "unrecognized", legacyReveal: true), .finder)
    }

    func testExplicitCompletionPreferenceWinsOverLegacy() {
        XCTAssertEqual(CompletionPresentation.resolve(stored: "card", legacyReveal: true), .card)
        XCTAssertEqual(CompletionPresentation.resolve(stored: "quiet", legacyReveal: true), .quiet)
        XCTAssertEqual(CompletionPresentation.resolve(stored: "finder", legacyReveal: false), .finder)
    }

    func testResultCardKeepsExistingRowsStableAndDeduplicates() {
        var results = CompletionResults()
        let a = URL(fileURLWithPath: "/tmp/ilk sonuç.png")
        let b = URL(fileURLWithPath: "/tmp/other.png")
        results.append([a]); results.append([a, b])
        XCTAssertEqual(results.urls, [a, b])
        XCTAssertEqual(results.omittedCount, 0)
    }

    func testResultCardIsBoundedAndNeverAcceptsRemoteURLs() {
        var results = CompletionResults()
        results.append([URL(string: "https://example.invalid/a")!])
        XCTAssertTrue(results.urls.isEmpty)
        let files = (0..<12).map { URL(fileURLWithPath: "/tmp/output-\($0).png") }
        results.append(files)
        XCTAssertEqual(results.urls, Array(files.prefix(8)))
        XCTAssertEqual(results.omittedCount, 4)
        results.removeAll()
        XCTAssertTrue(results.urls.isEmpty)
        XCTAssertEqual(results.omittedCount, 0)
    }
    func testSearchMatchesLocalizedTitlesAndMultipleTerms() {
        let ops = Catalog.tools(for: .image, count: 1)
        let titles = ["image.crop": "Görseli Kırp"]
        XCTAssertEqual(OperationDiscovery.matching(ops, query: "GÖRSELİ kırp", localizedTitles: titles).map(\.id), ["image.crop"])
        XCTAssertEqual(OperationDiscovery.matching(ops, query: "crop").map(\.id), ["image.crop"])
        XCTAssertEqual(OperationDiscovery.matching(ops, query: "   ").map(\.id), ops.map(\.id))
        XCTAssertTrue(OperationDiscovery.matching(ops, query: "not an operation").isEmpty)
    }

    func testFavoritesStoreOnlyBoundedIdentifiers() {
        let ids = ["image.crop", "image.crop", "/tmp/private-example.png", "", "convert.webp", "https://host/file"]
        XCTAssertEqual(OperationDiscovery.normalizedPins(ids), ["image.crop", "convert.webp"])
        XCTAssertEqual(OperationDiscovery.normalizedPins((0..<100).map { "convert.format\($0)" }).count, 12)
    }

    func testFavoritePresentationDoesNotChangeCatalogOrRadialOrdering() {
        let file = URL(fileURLWithPath: "/tmp/example.png")
        let before = Catalog.operations(for: [file], mode: .convert)
        let pins = ["convert.webp", "convert.jpg", "media.trim"]
        let presented = OperationDiscovery.pinned(from: before, identifiers: pins)
        XCTAssertEqual(presented.map(\.id), ["convert.webp", "convert.jpg"])
        XCTAssertEqual(Catalog.operations(for: [file], mode: .convert).map(\.id), before.map(\.id))
    }

}
