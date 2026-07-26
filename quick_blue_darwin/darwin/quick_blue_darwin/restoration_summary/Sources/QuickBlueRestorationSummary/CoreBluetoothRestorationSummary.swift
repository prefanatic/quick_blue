public enum RestoredPeripheralConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case unknown
}

public struct CoreBluetoothRestorationSummary: Equatable, Sendable {
    public let restoredPeripheralCount: Int
    public let disconnectedPeripheralCount: Int
    public let connectingPeripheralCount: Int
    public let connectedPeripheralCount: Int
    public let disconnectingPeripheralCount: Int
    public let unknownPeripheralCount: Int
    public let scanningRestored: Bool
    public let restoredScanServiceCount: Int

    public init(
        peripheralStates: [RestoredPeripheralConnectionState],
        hasRestoredScanServices: Bool,
        restoredScanServiceCount: Int,
        hasRestoredScanOptions: Bool
    ) {
        self.restoredPeripheralCount = peripheralStates.count
        self.disconnectedPeripheralCount = peripheralStates.count {
            $0 == .disconnected
        }
        self.connectingPeripheralCount = peripheralStates.count {
            $0 == .connecting
        }
        self.connectedPeripheralCount = peripheralStates.count {
            $0 == .connected
        }
        self.disconnectingPeripheralCount = peripheralStates.count {
            $0 == .disconnecting
        }
        self.unknownPeripheralCount = peripheralStates.count {
            $0 == .unknown
        }
        self.scanningRestored =
            hasRestoredScanServices || hasRestoredScanOptions
        self.restoredScanServiceCount = restoredScanServiceCount
    }
}
