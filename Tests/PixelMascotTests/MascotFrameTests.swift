import XCTest

@testable import PixelMascot

final class MascotFrameTests: XCTestCase {
    func testIdleFrameDimensions() {
        XCTAssertEqual(PixelMascot.idleFrame.width, 12)
        XCTAssertEqual(PixelMascot.idleFrame.height, 12)
        XCTAssertEqual(PixelMascot.idleFrame.rows.count, 12)
    }

    func testEachStateHasValidFrame() {
        for state in MascotState.allCases {
            let frame = PixelMascot.frame(for: state)
            XCTAssertEqual(frame.width, 12, "\(state) frame width")
            XCTAssertEqual(frame.height, 12, "\(state) frame height")
            XCTAssertEqual(frame.rows.count, 12, "\(state) row count")
            for (idx, row) in frame.rows.enumerated() {
                XCTAssertEqual(row.count, 12, "\(state) row \(idx) length")
            }
        }
    }

    func testFramesDifferBetweenStates() {
        let idle = PixelMascot.frame(for: .idle)
        let thinking = PixelMascot.frame(for: .thinking)
        let speaking = PixelMascot.frame(for: .speaking)
        let error = PixelMascot.frame(for: .error)
        let listening = PixelMascot.frame(for: .listening)

        XCTAssertNotEqual(idle, thinking)
        XCTAssertNotEqual(idle, speaking)
        XCTAssertNotEqual(idle, error)
        XCTAssertNotEqual(speaking, thinking)
        // Sprint 50: listening idle'dan görsel olarak farklı (geniş gözler).
        XCTAssertNotEqual(idle, listening)
        XCTAssertNotEqual(listening, speaking)
    }

    func testListeningFrameHasWiderEyesThanIdle() {
        // Sprint 50: listening gözleri 2 hücre genişliğinde (x=3,4 ve x=7,8);
        // idle'da göz tek hücre (x=3, x=8) → x=4/x=7 body ("X").
        let idle = PixelMascot.idleFrame
        let listening = PixelMascot.listeningFrame
        // İç göz hücreleri: idle'da body, listening'de göz.
        XCTAssertEqual(idle.cell(x: 4, y: 4), "X")
        XCTAssertEqual(listening.cell(x: 4, y: 4), "O")
        XCTAssertEqual(idle.cell(x: 7, y: 4), "X")
        XCTAssertEqual(listening.cell(x: 7, y: 4), "O")
        // Ağız idle gibi kapalı (`_`), konuşma ağzı (`M`) değil.
        XCTAssertEqual(listening.cell(x: 5, y: 6), "_")
    }

    func testCellOutOfBoundsReturnsDot() {
        let frame = PixelMascot.idleFrame
        XCTAssertEqual(frame.cell(x: -1, y: 0), ".")
        XCTAssertEqual(frame.cell(x: 100, y: 0), ".")
        XCTAssertEqual(frame.cell(x: 0, y: -1), ".")
        XCTAssertEqual(frame.cell(x: 0, y: 100), ".")
    }

    func testCornerCellsTransparent() {
        for state in MascotState.allCases {
            let frame = PixelMascot.frame(for: state)
            XCTAssertEqual(frame.cell(x: 0, y: 0), ".", "\(state) top-left")
            XCTAssertEqual(frame.cell(x: 11, y: 0), ".", "\(state) top-right")
            XCTAssertEqual(frame.cell(x: 0, y: 11), ".", "\(state) bottom-left")
            XCTAssertEqual(frame.cell(x: 11, y: 11), ".", "\(state) bottom-right")
        }
    }

    func testCustomAsciiPadsRows() {
        let frame = MascotFrame(ascii: "X\nXX", width: 5, height: 3)
        XCTAssertEqual(frame.rows.count, 3)
        XCTAssertEqual(frame.rows[0], "X....")
        XCTAssertEqual(frame.rows[1], "XX...")
        XCTAssertEqual(frame.rows[2], ".....")
    }
}
