import XCTest

@testable import QuickBlueRestorationSummary

final class CoreBluetoothRestorationSummaryTests: XCTestCase {
    func testMapsPeripheralStatesToPrivacySafeAggregateCounts() {
        let summary = CoreBluetoothRestorationSummary(
            peripheralStates: [
                .disconnected,
                .connecting,
                .connected,
                .connected,
                .disconnecting,
                .unknown,
            ],
            hasRestoredScanServices: false,
            restoredScanServiceCount: 0,
            hasRestoredScanOptions: false
        )

        XCTAssertEqual(summary.restoredPeripheralCount, 6)
        XCTAssertEqual(summary.disconnectedPeripheralCount, 1)
        XCTAssertEqual(summary.connectingPeripheralCount, 1)
        XCTAssertEqual(summary.connectedPeripheralCount, 2)
        XCTAssertEqual(summary.disconnectingPeripheralCount, 1)
        XCTAssertEqual(summary.unknownPeripheralCount, 1)
    }

    func testReportsRestoredScanningFromEitherCoreBluetoothScanKey() {
        for (hasServices, serviceCount, hasOptions) in [
            (true, 2, false),
            (false, 0, true),
        ] {
            let summary = CoreBluetoothRestorationSummary(
                peripheralStates: [],
                hasRestoredScanServices: hasServices,
                restoredScanServiceCount: serviceCount,
                hasRestoredScanOptions: hasOptions
            )

            XCTAssertTrue(summary.scanningRestored)
            XCTAssertEqual(
                summary.restoredScanServiceCount,
                serviceCount
            )
        }
    }

    func testReportsScanningAsNotRestoredWhenNeitherScanKeyIsPresent() {
        let summary = CoreBluetoothRestorationSummary(
            peripheralStates: [],
            hasRestoredScanServices: false,
            restoredScanServiceCount: 0,
            hasRestoredScanOptions: false
        )

        XCTAssertFalse(summary.scanningRestored)
        XCTAssertEqual(summary.restoredScanServiceCount, 0)
    }
}
