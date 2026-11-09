// Linux stub of Apple CoreBluetooth, for type-checking only.
// Signature-faithful subset used by QuickBlueDarwinPlugin.swift and Messages.g.swift.
import Foundation

public typealias CBL2CAPPSM = UInt16

// MARK: - Constants (keys are String in the real framework)

public let CBAdvertisementDataManufacturerDataKey = "kCBAdvDataManufacturerData"
public let CBAdvertisementDataServiceDataKey = "kCBAdvDataServiceData"
public let CBAdvertisementDataServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
public let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"
public let CBCentralManagerScanOptionSolicitedServiceUUIDsKey = "kCBScanOptionSolicitedServiceUUIDs"
public let CBCentralManagerOptionRestoreIdentifierKey = "kCBCentralManagerOptionRestoreIdentifierKey"
public let CBCentralManagerRestoredStatePeripheralsKey = "kCBCentralManagerRestoredStatePeripheralsKey"
public let CBCentralManagerRestoredStateScanOptionsKey = "kCBCentralManagerRestoredStateScanOptionsKey"
public let CBCentralManagerRestoredStateScanServicesKey = "kCBCentralManagerRestoredStateScanServicesKey"

// MARK: - Value types

open class CBUUID: NSObject {
    public let uuidString: String
    public let data: Data
    public init(string: String) {
        self.uuidString = string
        self.data = Data()
    }
    public init(data: Data) {
        self.data = data
        self.uuidString = data.map { String(format: "%02x", $0) }.joined()
    }
    public init(nsuuid: UUID) {
        self.uuidString = nsuuid.uuidString
        self.data = Data()
    }
}

public struct CBCharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let broadcast = CBCharacteristicProperties(rawValue: 1 << 0)
    public static let read = CBCharacteristicProperties(rawValue: 1 << 1)
    public static let writeWithoutResponse = CBCharacteristicProperties(rawValue: 1 << 2)
    public static let write = CBCharacteristicProperties(rawValue: 1 << 3)
    public static let notify = CBCharacteristicProperties(rawValue: 1 << 4)
    public static let indicate = CBCharacteristicProperties(rawValue: 1 << 5)
    public static let authenticatedSignedWrites = CBCharacteristicProperties(rawValue: 1 << 6)
    public static let extendedProperties = CBCharacteristicProperties(rawValue: 1 << 7)
    public static let notifyEncryptionRequired = CBCharacteristicProperties(rawValue: 1 << 8)
    public static let indicateEncryptionRequired = CBCharacteristicProperties(rawValue: 1 << 9)
}

public enum CBManagerState: Int, Sendable {
    case unknown = 0
    case resetting = 1
    case unsupported = 2
    case unauthorized = 3
    case poweredOff = 4
    case poweredOn = 5
}

public enum CBManagerAuthorization: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case allowedAlways = 3
}

public enum CBPeripheralState: Int, Sendable {
    case disconnected = 0
    case connecting = 1
    case connected = 2
    case disconnecting = 3
}

public enum CBCharacteristicWriteType: Int, Sendable {
    case withResponse = 0
    case withoutResponse = 1
}

// MARK: - Objects

open class CBAttribute: NSObject {
    open var uuid: CBUUID = CBUUID(string: "")
}

open class CBDescriptor: CBAttribute {
    open var characteristic: CBCharacteristic?
    open var value: Any?
}

open class CBCharacteristic: CBAttribute {
    open var service: CBService?
    open var value: Data?
    open var properties: CBCharacteristicProperties = []
    open var descriptors: [CBDescriptor]?
    open var isNotifying: Bool = false
    open var isBroadcasted: Bool = false
}

open class CBService: CBAttribute {
    open var isPrimary: Bool = false
    open var characteristics: [CBCharacteristic]?
    open var includedServices: [CBService]?
    open var peripheral: CBPeripheral?
}

open class CBPeer: NSObject {
    open var identifier: UUID = UUID()
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?)
}

open class CBPeripheral: CBPeer {
    open var name: String?
    open var delegate: CBPeripheralDelegate?
    open var services: [CBService]?
    open var state: CBPeripheralState = .disconnected
    open var canSendWriteWithoutResponse: Bool = false
    open var rssi: NSNumber?

    open func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    open func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService) {}
    open func discoverDescriptors(for characteristic: CBCharacteristic) {}
    open func discoverIncludedServices(_ serviceUUIDs: [CBUUID]?, for service: CBService) {}
    open func readValue(for characteristic: CBCharacteristic) {}
    open func readValue(for descriptor: CBDescriptor) {}
    open func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {}
    open func writeValue(_ data: Data, for descriptor: CBDescriptor) {}
    open func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    open func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { 0 }
    open func readRSSI() {}
    open func openL2CAPChannel(_ PSM: CBL2CAPPSM) {}
}

open class CBL2CAPChannel: NSObject {
    open var inputStream: InputStream { fatalError("CoreBluetooth stub") }
    open var outputStream: OutputStream { fatalError("CoreBluetooth stub") }
    open var peer: CBPeer { fatalError("CoreBluetooth stub") }
    open var psm: CBL2CAPPSM { fatalError("CoreBluetooth stub") }
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

open class CBManager: NSObject {
    open var state: CBManagerState = .unknown
    public static var authorization: CBManagerAuthorization { .allowedAlways }
}

open class CBCentralManager: CBManager {
    // Harness-only fixtures for exercising the real plugin against native stubs.
    public static var testPeripherals: [CBPeripheral] = []
    public static weak var testInstance: CBCentralManager?
    open var delegate: CBCentralManagerDelegate?
    open var isScanning: Bool = false

    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]? = nil) {
        super.init()
        self.delegate = delegate
        Self.testInstance = self
    }

    open func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
    open func stopScan() {}
    open func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {}
    open func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    open func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { [] }
    open func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
        Self.testPeripherals.filter { identifiers.contains($0.identifier) }
    }
}

#if os(Linux)
    /// Linux-corelibs-Foundation compatibility shim (not part of Apple CoreBluetooth).
    ///
    /// Apple's `OutputStream.write(_:maxLength:)` is imported from the
    /// Objective-C NSOutputStream header, and calls to C-imported functions
    /// accept an implicit `UnsafeRawPointer` -> `UnsafePointer<UInt8>`
    /// conversion. That is what lets QuickBlueDarwinPlugin's `sendData()` pass
    /// `Data.withUnsafeBytes`' `baseAddress!` straight through. On Linux,
    /// swift-corelibs-foundation declares the same method in Swift, so the
    /// implicit conversion is rejected with "instance method
    /// 'write(_:maxLength:)' was not imported from C header". This overload
    /// restores the macOS call shape so the plugin can be type-checked here.
    public extension OutputStream {
        @_disfavoredOverload
        func write(_ buffer: UnsafeRawPointer, maxLength len: Int) -> Int {
            write(buffer.assumingMemoryBound(to: UInt8.self), maxLength: len)
        }
    }
#endif
