import XCTest

@testable import QuickBlueRestorationSummary

final class CoreBluetoothRestorationBootstrapPolicyTests: XCTestCase {
    func testUsesDocumentedInfoPlistKey() {
        XCTAssertEqual(
            CoreBluetoothRestorationBootstrapPolicy.infoPlistKey,
            "QuickBlueCoreBluetoothStateRestorationEnabled"
        )
    }

    func testReadsPersistentOptInFromInfoPlist() {
        let policy = CoreBluetoothRestorationBootstrapPolicy(
            infoDictionary: [
                CoreBluetoothRestorationBootstrapPolicy.infoPlistKey: true
            ]
        )

        XCTAssertTrue(policy.persistentOptIn)
        XCTAssertTrue(policy.shouldBootstrapAtRegistration)
    }

    func testRequiresBooleanTrueForPersistentOptIn() {
        for value: Any? in [nil, false, "true", 1] {
            let infoDictionary: [String: Any]
            if let value = value {
                infoDictionary = [
                    CoreBluetoothRestorationBootstrapPolicy.infoPlistKey: value
                ]
            } else {
                infoDictionary = [:]
            }

            let policy = CoreBluetoothRestorationBootstrapPolicy(
                infoDictionary: infoDictionary
            )
            XCTAssertFalse(policy.persistentOptIn)
            XCTAssertFalse(policy.shouldBootstrapAtRegistration)
        }
    }

    func testPersistentOptInOverridesRuntimeFalse() {
        let policy = CoreBluetoothRestorationBootstrapPolicy(
            persistentOptIn: true
        )

        XCTAssertTrue(policy.effectiveMaintainState(requestedByDart: false))
    }

    func testRuntimeOptInRemainsAvailableWithoutPersistentSetting() {
        let policy = CoreBluetoothRestorationBootstrapPolicy(
            persistentOptIn: false
        )

        XCTAssertTrue(policy.effectiveMaintainState(requestedByDart: true))
        XCTAssertFalse(policy.effectiveMaintainState(requestedByDart: false))
    }
}
