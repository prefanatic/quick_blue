public struct CoreBluetoothRestorationBootstrapPolicy: Sendable {
    public static let infoPlistKey =
        "QuickBlueCoreBluetoothStateRestorationEnabled"

    public let persistentOptIn: Bool

    public init(infoDictionary: [String: Any]) {
        self.persistentOptIn =
            infoDictionary[Self.infoPlistKey] as? Bool == true
    }

    public init(persistentOptIn: Bool) {
        self.persistentOptIn = persistentOptIn
    }

    public var shouldBootstrapAtRegistration: Bool {
        persistentOptIn
    }

    public func effectiveMaintainState(requestedByDart: Bool) -> Bool {
        persistentOptIn || requestedByDart
    }
}
