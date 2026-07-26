import XCTest

@testable import QuickBlueRestorationSummary

final class BufferedRestorationEventDeliveryTests: XCTestCase {
    func testReplaysBufferedEventsOnceInCallbackOrder() {
        let delivery = BufferedRestorationEventDelivery<Int>()
        delivery.emit(1)
        delivery.emit(2)

        var received: [Int] = []
        delivery.start { received.append($0) }
        delivery.start { received.append($0) }

        XCTAssertEqual(received, [1, 2])
    }

    func testDeliversEachLiveEventOnce() {
        let delivery = BufferedRestorationEventDelivery<Int>()
        var received: [Int] = []
        delivery.start { received.append($0) }

        delivery.emit(1)
        delivery.emit(2)

        XCTAssertEqual(received, [1, 2])
    }

    func testBuffersAgainAfterDeliveryStops() {
        let delivery = BufferedRestorationEventDelivery<Int>()
        var received: [Int] = []
        delivery.start { received.append($0) }
        delivery.stop()
        delivery.emit(1)

        XCTAssertTrue(received.isEmpty)
        delivery.start { received.append($0) }
        XCTAssertEqual(received, [1])
    }
}
