import XCTest
@testable import PixelLAN

final class LANTXTRecordTests: XCTestCase {
    func testEncodeEmptyEntriesProducesEmptyData() {
        let data = LANTXTRecord.encode([:])
        XCTAssertTrue(data.isEmpty)
    }

    func testEncodeSingleEntryWireFormat() {
        let data = LANTXTRecord.encode(["pk": "ABC"])
        // <length-byte><pk=ABC> → 6 byte: 0x06 'p' 'k' '=' 'A' 'B' 'C'
        XCTAssertEqual(data.count, 7)
        XCTAssertEqual(data[0], 6)
        let entry = String(data: data.subdata(in: 1..<data.endIndex), encoding: .utf8)
        XCTAssertEqual(entry, "pk=ABC")
    }

    func testEncodeMultipleEntriesAreAlphabeticallySorted() {
        // "v" alfabetik olarak "pk"'den sonra; sıralı çıkmalı (deterministic encoding)
        let data = LANTXTRecord.encode(["v": "2", "pk": "key"])
        let decoded = LANTXTRecord.decode(data)
        XCTAssertEqual(decoded, ["pk": "key", "v": "2"])

        // Wire'da pk önce gelmeli ("p" < "v")
        let firstLen = Int(data[0])
        let firstEntry = String(data: data.subdata(in: 1..<(1 + firstLen)), encoding: .utf8)
        XCTAssertEqual(firstEntry, "pk=key")
    }

    func testEncodeRoundtripPreservesValues() {
        let entries = [
            "pk": "BASE64KEY==",
            "v": "v2",
        ]
        let decoded = LANTXTRecord.decode(LANTXTRecord.encode(entries))
        XCTAssertEqual(decoded, entries)
    }

    func testEncodeSkipsOverlyLongEntries() {
        // 250 byte değer → "pk=...." 253 byte (3 + 250) — sınırın altında, geçer
        let okValue = String(repeating: "a", count: 250)
        let okData = LANTXTRecord.encode(["pk": okValue])
        XCTAssertFalse(okData.isEmpty)

        // 300 byte değer → toplam entry 303 byte; >255 — atlanmalı
        let bigValue = String(repeating: "a", count: 300)
        let bigData = LANTXTRecord.encode(["pk": bigValue])
        XCTAssertTrue(bigData.isEmpty)
    }

    func testDecodeIgnoresMalformedEntries() {
        // length 5 ama buffer'da sadece 3 byte var → loop break, partial parse
        let bytes: [UInt8] = [3, 0x61, 0x3D, 0x62, /* "a=b" 4. byte yok */ 5, 0x66]
        let decoded = LANTXTRecord.decode(Data(bytes))
        XCTAssertEqual(decoded, ["a": "b"])
    }
}
