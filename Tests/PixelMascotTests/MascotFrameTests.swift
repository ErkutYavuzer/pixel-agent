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

        XCTAssertNotEqual(idle, thinking)
        XCTAssertNotEqual(idle, speaking)
        XCTAssertNotEqual(idle, error)
        XCTAssertNotEqual(speaking, thinking)
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
