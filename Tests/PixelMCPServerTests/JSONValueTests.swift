import XCTest
@testable import PixelMCPServer

final class JSONValueTests: XCTestCase {
    func testRoundTripPrimitives() throws {
        let values: [JSONValue] = [.null, .bool(true), .int(42), .double(3.14), .string("merhaba")]
        for v in values {
            let data = try JSONEncoder().encode(v)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, v)
        }
    }

    func testRoundTripObject() throws {
        let v: JSONValue = .object([
            "name": .string("pixel"),
            "count": .int(5),
            "flags": .array([.string("a"), .string("b")]),
        ])
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, v)
    }

    func testNestedSubscript() {
        let v: JSONValue = .object([
            "params": .object([
                "name": .string("get_clipboard"),
                "arguments": .object([:]),
            ]),
        ])
        XCTAssertEqual(v["params"]?["name"]?.stringValue, "get_clipboard")
        XCTAssertNil(v["params"]?["missing"])
    }

    func testTypedAccessors() {
        XCTAssertEqual(JSONValue.string("x").stringValue, "x")
        XCTAssertEqual(JSONValue.int(7).intValue, 7)
        XCTAssertEqual(JSONValue.bool(false).boolValue, false)
        XCTAssertEqual(JSONValue.array([.int(1)]).arrayValue, [.int(1)])
        XCTAssertNil(JSONValue.null.stringValue)
    }

    func testDecodeFromJSONString() throws {
        let json = #"{"a":1,"b":"x","c":true,"d":null,"e":[1,2]}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        XCTAssertEqual(v["a"]?.intValue, 1)
        XCTAssertEqual(v["b"]?.stringValue, "x")
        XCTAssertEqual(v["c"]?.boolValue, true)
        if case .null = v["d"] {} else { XCTFail("d null değil") }
        XCTAssertEqual(v["e"]?.arrayValue?.count, 2)
    }
}
