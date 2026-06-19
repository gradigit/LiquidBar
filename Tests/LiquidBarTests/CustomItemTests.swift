import Testing
import Foundation
@testable import LiquidBar

@Suite
struct CustomItemTests {
    @Test func testCodableRoundtrip() throws {
        let items: [CustomItem] = [
            .spacer(id: "s1", width: 12),
            .text(id: "t1", text: "Hello"),
            .link(id: "l1", title: "GitHub", url: "https://github.com", icon: "sf:link"),
            .folder(id: "f1", title: "Downloads", path: "/Users/me/Downloads", icon: "file:/Users/me/Downloads"),
        ]

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        let data = try enc.encode(items)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try dec.decode([CustomItem].self, from: data)

        #expect(decoded == items)
    }

    @Test func testDecodeMissingIdGeneratesOne() throws {
        let json = """
        { "type": "text", "text": "Hello" }
        """
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let item = try dec.decode(CustomItem.self, from: json.data(using: .utf8)!)

        if case .text(let id, let text) = item {
            #expect(!id.isEmpty)
            #expect(text == "Hello")
        } else {
            Issue.record("expected text item")
        }
    }

    @Test func testConfigValidateClampsSpacerWidth() {
        var config = Config(customItems: [.spacer(id: "s1", width: 9999)])
        config.validate()
        #expect(config.customItems == [.spacer(id: "s1", width: 240)])
    }
}

