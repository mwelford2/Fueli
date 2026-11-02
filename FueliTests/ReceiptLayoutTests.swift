import Foundation
import Testing
@testable import Fueli

struct ReceiptLayoutTests {
    struct Annotation: Decodable {
        var text: String; var skip: Bool; var name: String?
        var quantity: Double?; var unit: String?; var confidence: Float
    }
    @Test func annotatedReceiptRowsSeparateFoodAndMetadataWithoutAutoConfirmation() throws {
        let bundle = Bundle(for: ReceiptLayoutFixture.self)
        let url = try #require(bundle.url(forResource: "annotated-rows", withExtension: "json"))
        let annotations = try JSONDecoder().decode([Annotation].self, from: Data(contentsOf: url))
        #expect(annotations.count == 25)
        for expected in annotations {
            let row = ReceiptParser.parse(expected.text, confidence: expected.confidence)
            #expect(row.original == expected.text)
            #expect(row.skip == expected.skip, "Classification: \(expected.text)")
            if let name = expected.name { #expect(row.name == name) }
            #expect(row.purchaseQuantity == expected.quantity)
            #expect(row.purchaseUnit == expected.unit)
            #expect(!row.imported)
            if expected.confidence < 0.8 { #expect(row.confidence < 0.8) }
        }
    }
    @Test func longReceiptReconstructsNamesAndPricesAtSeparateCoordinates() {
        var fragments: [ReceiptParser.Fragment] = []
        for index in 0..<130 {
            let y = 0.98 - Double(index) * 0.006
            fragments.append(.init(text: index.isMultiple(of: 2) ? "YGRT" : "CASHEWS", x: 0.05, y: y, height: 0.003, confidence: 0.9))
            fragments.append(.init(text: "1.99", x: 0.8, y: y + 0.0005, height: 0.003, confidence: 0.85))
        }
        fragments.append(.init(text: "TAX: 0.39", x: 0.05, y: 0.18, height: 0.003, confidence: 0.9))
        let rows = ReceiptParser.reconstruct(Array(fragments.reversed()))
        #expect(rows.count == 131)
        #expect(rows.filter { $0.name == "yogurt" }.count == 65)
        #expect(rows.filter { $0.name == "cashews" }.count == 65)
        #expect(rows.last?.skip == true)
        #expect(Set(rows.map(\.id)).count == 131)
        #expect(rows.allSatisfy { !$0.imported && $0.purchaseQuantity == nil })
    }
    @Test func multiplePagesAndOverlapRemainExplicitUnresolvedPurchases() {
        let pages = [["CHK BRST 1.5 LB 8.99", "YGRT 1.99"], ["YGRT 1.99", "ORG APPLES 2.99"], ["COUPON -1.00", "TOTAL: 14.96"]]
        let rows = pages.flatMap { page in page.map { ReceiptParser.parse($0, confidence: 0.65) } }
        #expect(rows.count == 6 && rows.filter(\.skip).count == 2)
        #expect(rows.filter { $0.name == "yogurt" }.count == 2)
        // Overlap cannot safely be distinguished from repeat purchases by text alone.
        #expect(rows.allSatisfy { !$0.imported })
        #expect(Set(rows.map(\.id)).count == 6)
    }
}
private final class ReceiptLayoutFixture {}
