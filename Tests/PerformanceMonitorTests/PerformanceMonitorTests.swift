import XCTest
@testable import PerformanceMonitor

final class PerformanceMonitorTests: XCTestCase {
    func testDesktopPanelUsesLeftBottomMargin() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let result = DesktopPosition.frame(
            visibleFrame: visibleFrame,
            panelSize: DesktopPosition.panelSize,
            margin: 16
        )

        XCTAssertEqual(result.origin.x, 16)
        XCTAssertEqual(result.origin.y, 56)
        XCTAssertEqual(result.size.width, 360)
        XCTAssertEqual(result.size.height, 684)
    }

    func testHistoryRangesMatchExpectedDurations() {
        XCTAssertEqual(HistoryRange.hour.interval, 3_600)
        XCTAssertEqual(HistoryRange.day.interval, 86_400)
        XCTAssertEqual(HistoryRange.week.interval, 604_800)
    }

    func testDraggedPanelIsKeptInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let offscreenFrame = CGRect(
            x: -180,
            y: 720,
            width: DesktopPosition.panelSize.width,
            height: DesktopPosition.panelSize.height
        )
        let result = DesktopPosition.constrainedFrame(
            offscreenFrame,
            within: visibleFrame
        )

        XCTAssertEqual(result.minX, visibleFrame.minX)
        XCTAssertEqual(result.maxY, visibleFrame.maxY)
        XCTAssertEqual(result.size.width, 360)
        XCTAssertEqual(result.size.height, 684)
    }

    func testIncreasingHeightKeepsPanelTopInPlace() {
        let result = DesktopPosition.originKeepingTop(
            origin: CGPoint(x: 80, y: 240),
            previousHeight: 620,
            newHeight: 684
        )

        XCTAssertEqual(result.x, 80)
        XCTAssertEqual(result.y, 176)
    }

    func testProcessSortingCanSwitchBetweenCPUAndMemory() {
        let processes = [
            ProcessUsage(id: 1, name: "内存应用", cpuPercent: 8, memoryMB: 900),
            ProcessUsage(id: 2, name: "CPU应用", cpuPercent: 70, memoryMB: 120),
            ProcessUsage(id: 3, name: "普通应用", cpuPercent: 20, memoryMB: 300)
        ]

        XCTAssertEqual(ProcessSortMetric.cpu.sorted(processes).first?.name, "CPU应用")
        XCTAssertEqual(ProcessSortMetric.memory.sorted(processes).first?.name, "内存应用")
    }

}
