import XCTest

@testable import QuickBlueConnectionOwnership

final class SharedConnectionOwnershipTests: XCTestCase {
    private final class Client {}

    private struct NotificationKey: Hashable {
        let service: String
        let characteristic: String
    }

    private enum Property {
        case disabled
        case notification
        case indication
    }

    private typealias Ownership = SharedConnectionOwnership<
        String,
        Client,
        NotificationKey,
        Property
    >

    func testAttachSharesOriginalHostAndTracksClients() {
        let ownership = Ownership()
        let host = Client()
        let client = Client()

        let first = ownership.attach("device", client: host)
        let second = ownership.attach("device", client: client)

        XCTAssertTrue(first.isNew)
        XCTAssertTrue(first.host === host)
        XCTAssertFalse(second.isNew)
        XCTAssertTrue(second.host === host)
        XCTAssertTrue(ownership.host(for: "device", client: client) === host)
        XCTAssertEqual(ownership.clients(for: "device").count, 2)
        XCTAssertEqual(ownership.deviceIds(for: client), ["device"])
    }

    func testDetachReleasesNotificationsAfterLastClaim() {
        let ownership = Ownership()
        let first = Client()
        let second = Client()
        let key = NotificationKey(service: "service", characteristic: "value")
        _ = ownership.attach("device", client: first)
        _ = ownership.attach("device", client: second)

        XCTAssertAccepted(
            ownership.updateNotificationClaim(
                deviceId: "device",
                key: key,
                client: first,
                property: .notification,
                disabledProperty: .disabled
            ),
            needsNativeWrite: true
        )
        XCTAssertAccepted(
            ownership.updateNotificationClaim(
                deviceId: "device",
                key: key,
                client: second,
                property: .notification,
                disabledProperty: .disabled
            ),
            needsNativeWrite: false
        )

        let firstPlan = ownership.detach(
            "device",
            client: first,
            preserveFinalClient: false
        )
        XCTAssertEqual(firstPlan?.notificationsToDisable, [])
        XCTAssertFalse(firstPlan?.shouldDisconnect ?? true)

        let secondPlan = ownership.detach(
            "device",
            client: second,
            preserveFinalClient: false
        )
        XCTAssertEqual(secondPlan?.notificationsToDisable, [key])
        XCTAssertTrue(secondPlan?.shouldDisconnect ?? false)
    }

    func testNotificationClaimsRejectConflictingProperties() {
        let ownership = Ownership()
        let first = Client()
        let second = Client()
        let key = NotificationKey(service: "service", characteristic: "value")
        _ = ownership.attach("device", client: first)
        _ = ownership.attach("device", client: second)
        _ = ownership.updateNotificationClaim(
            deviceId: "device",
            key: key,
            client: first,
            property: .notification,
            disabledProperty: .disabled
        )

        let result = ownership.updateNotificationClaim(
            deviceId: "device",
            key: key,
            client: second,
            property: .indication,
            disabledProperty: .disabled
        )

        guard case .conflicting = result else {
            return XCTFail("Expected a conflicting notification claim")
        }
    }

    func testDisablingWithoutAClaimStillRequestsNativeCleanup() {
        let ownership = Ownership()
        let client = Client()
        let key = NotificationKey(service: "service", characteristic: "value")
        _ = ownership.attach("device", client: client)

        XCTAssertAccepted(
            ownership.updateNotificationClaim(
                deviceId: "device",
                key: key,
                client: client,
                property: .disabled,
                disabledProperty: .disabled
            ),
            needsNativeWrite: true
        )
    }

    func testFailedNotificationUpdateCanRestorePreviousClaim() {
        let ownership = Ownership()
        let first = Client()
        let second = Client()
        let key = NotificationKey(service: "service", characteristic: "value")
        _ = ownership.attach("device", client: first)
        _ = ownership.attach("device", client: second)
        _ = ownership.updateNotificationClaim(
            deviceId: "device",
            key: key,
            client: first,
            property: .notification,
            disabledProperty: .disabled
        )

        let update = ownership.updateNotificationClaim(
            deviceId: "device",
            key: key,
            client: first,
            property: .disabled,
            disabledProperty: .disabled
        )
        guard case .accepted(let needsNativeWrite, let previousProperty) = update
        else {
            return XCTFail("Expected an accepted claim")
        }
        XCTAssertTrue(needsNativeWrite)
        XCTAssertEqual(previousProperty, .notification)

        ownership.restoreNotificationClaim(
            deviceId: "device",
            key: key,
            client: first,
            property: previousProperty
        )
        XCTAssertAccepted(
            ownership.updateNotificationClaim(
                deviceId: "device",
                key: key,
                client: second,
                property: .notification,
                disabledProperty: .disabled
            ),
            needsNativeWrite: false
        )
    }

    func testEngineDetachGraceCanBeClaimedOrCleanedUp() {
        let ownership = Ownership()
        let host = Client()
        _ = ownership.attach("device", client: host)

        let plan = ownership.detach(
            "device",
            client: host,
            preserveFinalClient: false,
            preserveEmptyConnection: true
        )

        XCTAssertTrue(plan?.shouldDisconnect ?? false)
        XCTAssertFalse(ownership.takeUnclaimedConnection("device", host: Client()))

        let replacement = Client()
        let attachment = ownership.attach("device", client: replacement)
        XCTAssertFalse(attachment.isNew)
        XCTAssertTrue(attachment.host === host)
        XCTAssertFalse(ownership.takeUnclaimedConnection("device", host: host))

        _ = ownership.detach(
            "device",
            client: replacement,
            preserveFinalClient: false,
            preserveEmptyConnection: true
        )
        XCTAssertTrue(ownership.takeUnclaimedConnection("device", host: host))
        XCTAssertFalse(ownership.isHostingConnections(host))
    }

    private func XCTAssertAccepted(
        _ result: Ownership.NotificationClaimUpdate,
        needsNativeWrite: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .accepted(let actual, _) = result else {
            return XCTFail("Expected an accepted claim", file: file, line: line)
        }
        XCTAssertEqual(actual, needsNativeWrite, file: file, line: line)
    }
}
