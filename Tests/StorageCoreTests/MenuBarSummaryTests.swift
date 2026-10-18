import XCTest
@testable import StorageCore

final class MenuBarSummaryTests: XCTestCase {
    private let volume = Volume(id: "fixture", url: URL(fileURLWithPath: "/"), name: "Disk", total: 100 * 1_073_741_824, available: 25 * 1_073_741_824, local: true, removable: false)
    func testAllDisplayModesUseRealCapacity() {
        XCTAssertEqual(MenuBarSummary.label(volume: volume, display: .available), "25.0 GiB")
        XCTAssertEqual(MenuBarSummary.label(volume: volume, display: .used), "75.0 GiB")
        XCTAssertEqual(MenuBarSummary.label(volume: volume, display: .percentage), "75%")
    }
    func testUnavailableVolumeNeverDisplaysZeroCapacityOrWarning() {
        XCTAssertEqual(MenuBarSummary.label(volume: nil, display: .available), "Storage —")
        XCTAssertFalse(MenuBarSummary.isLow(volume: nil, warningGB: 50))
    }
    func testWarningThresholdUsesGiBAndStrictBoundary() {
        XCTAssertTrue(MenuBarSummary.isLow(volume: volume, warningGB: 26))
        XCTAssertFalse(MenuBarSummary.isLow(volume: volume, warningGB: 25))
    }
}
