import XCTest
@testable import PerformanceMonitor

final class PerformanceMonitorTests: XCTestCase {
    func testDesktopPanelUsesLeftBottomMargin() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let result = DesktopPosition.frame(
            visibleFrame: visibleFrame,
            panelSize: CGSize(width: 360, height: 620),
            margin: 16
        )

        XCTAssertEqual(result.origin.x, 16)
        XCTAssertEqual(result.origin.y, 56)
        XCTAssertEqual(result.size.width, 360)
        XCTAssertEqual(result.size.height, 620)
    }

    func testHistoryRangesMatchExpectedDurations() {
        XCTAssertEqual(HistoryRange.hour.interval, 3_600)
        XCTAssertEqual(HistoryRange.day.interval, 86_400)
        XCTAssertEqual(HistoryRange.week.interval, 604_800)
    }

    func testDraggedPanelIsKeptInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let offscreenFrame = CGRect(x: -180, y: 720, width: 360, height: 620)
        let result = DesktopPosition.constrainedFrame(
            offscreenFrame,
            within: visibleFrame
        )

        XCTAssertEqual(result.minX, visibleFrame.minX)
        XCTAssertEqual(result.maxY, visibleFrame.maxY)
        XCTAssertEqual(result.size.width, 360)
        XCTAssertEqual(result.size.height, 620)
    }
}
