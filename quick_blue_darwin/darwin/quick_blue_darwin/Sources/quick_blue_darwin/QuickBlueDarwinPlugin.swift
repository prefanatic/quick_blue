import Foundation
import CoreBluetooth

#if os(iOS)
    import Flutter
#elseif os(OSX)
    import FlutterMacOS
#endif

let GSS_SUFFIX = "0000-1000-8000-00805f9b34fb"

extension CBUUID {
    public var uuidStr: String {
        uuidString.lowercased()
    }
}

extension CBCharacteristic {
    var platformCharacteristic: PlatformCharacteristic {
        PlatformCharacteristic(
            uuid: uuid.uuidStr,
            canRead: properties.contains(.read),
            canWriteWithResponse: properties.contains(.write),
            canWriteWithoutResponse: properties.contains(.writeWithoutResponse),
            canNotify: properties.contains(.notify),
            canIndicate: properties.contains(.indicate)
        )
    }
}

extension CBPeripheral {
    public func getCharacteristic(_ characteristic: String, of service: String)
        -> CBCharacteristic?
    {
        // CoreBluetooth reports UUIDs lowercased and 16-bit UUIDs in short form
        // (e.g. "180d"). Callers may pass uppercase and/or the full 128-bit GSS
        // form, so normalize both sides before comparing.
        let service = service.lowercased()
        let characteristic = characteristic.lowercased()
        let s = self.services?.first {
            $0.uuid.uuidStr == service
                || "0000\($0.uuid.uuidStr)-\(GSS_SUFFIX)" == service
        }
        let c = s?.characteristics?.first {
            $0.uuid.uuidStr == characteristic
                || "0000\($0.uuid.uuidStr)-\(GSS_SUFFIX)" == characteristic
        }
        return c
    }

    func setNotifiable(
        _ bleInputProperty: PlatformBleInputProperty,
        for characteristic: String,
        of service: String
    ) {
        setNotifyValue(
            bleInputProperty != PlatformBleInputProperty.disabled,
            for: getCharacteristic(characteristic, of: service)!
        )
    }
}

extension CBManagerState {
    var platformBluetoothState: PlatformBluetoothState {
        switch self {
        case .unknown, .resetting:
            return .unknown
        case .unsupported:
            return .unavailable
        case .unauthorized:
            return .unauthorized
        case .poweredOff:
            return .poweredOff
        case .poweredOn:
            return .poweredOn
        @unknown default:
            return .unknown
        }
    }
}

public class QuickBlueDarwinPlugin: NSObject, FlutterPlugin, QuickBlueApi {
    private static let connectionOwnerLock = NSLock()
    private static var connectionOwners: [String: UUID] = [:]

    private static func claimConnection(_ deviceId: String, owner: UUID) -> Bool {
        connectionOwnerLock.lock()
        defer { connectionOwnerLock.unlock() }
        if let existing = connectionOwners[deviceId], existing != owner {
            return false
        }
        connectionOwners[deviceId] = owner
        return true
    }

    private static func ownsConnection(_ deviceId: String, owner: UUID) -> Bool {
        connectionOwnerLock.lock()
        defer { connectionOwnerLock.unlock() }
        return connectionOwners[deviceId] == owner
    }

    @discardableResult
    private static func releaseConnection(_ deviceId: String, owner: UUID) -> Bool {
        connectionOwnerLock.lock()
        defer { connectionOwnerLock.unlock() }
        guard connectionOwners[deviceId] == owner else { return false }
        connectionOwners.removeValue(forKey: deviceId)
        return true
    }

    private static func releaseConnections(owner: UUID) {
        connectionOwnerLock.lock()
        defer { connectionOwnerLock.unlock() }
        connectionOwners = connectionOwners.filter { $0.value != owner }
    }

    private let connectionOwnerId = UUID()
    private var isAttachedToEngine = true

    func getConnectedPeripherals(serviceUuids: [String]) throws -> [Peripheral]
    {
        let peripherals = getManager().retrieveConnectedPeripherals(
            withServices: serviceUuids.map { uuid in CBUUID(string: uuid) }
        )
        for peripheral in peripherals {
            discoveredPeripherals[peripheral.identifier.uuidString] =
                peripheral
        }
        return peripherals.map { peripherals in
            Peripheral(
                id: peripherals.identifier.uuidString,
                name: peripherals.name ?? ""
            )
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
            let messenger = registrar.messenger()
        #elseif os(OSX)
            let messenger = registrar.messenger
        #endif

        let flutterApi = QuickBlueFlutterApi(binaryMessenger: messenger)
        let instance = QuickBlueDarwinPlugin(flutterApi: flutterApi)
        QuickBlueApiSetup.setUp(binaryMessenger: messenger, api: instance)
        BluetoothStateStreamHandler.register(
            with: messenger,
            streamHandler: instance.bluetoothStateListener
        )
        ScanResultListener.register(
            with: messenger,
            streamHandler: instance.scanResultListener
        )
        L2CapSocketEventsListener.register(
            with: messenger,
            streamHandler: instance.l2CapSocketEventsListener
        )
    }

    private let stateQueue = DispatchQueue(label: "quick_blue.state.queue")

    private var flutterApi: QuickBlueFlutterApi
    private var bluetoothStateListener: BluetoothStateListener
    private var scanResultListener: ScanResultListener
    private var l2CapSocketEventsListener: L2CapSocketEventsListener

    private var manager: CBCentralManager?
    private var maintainState = false
    private let restorationIdentifier =
        "\(Bundle.main.bundleIdentifier ?? "quick_blue").quick_blue.central"
    private var discoveredPeripherals: [String: CBPeripheral]!
    private var streamDelegates: [String: L2CapStreamDelegate]!
    private var pendingServiceDiscovery: [String: Set<String>]!

    // Completions for write-with-response calls awaiting their didWriteValueFor
    // acknowledgement, keyed by "deviceId/characteristicId". CoreBluetooth
    // serializes writes and delivers acknowledgements in order, so each key
    // holds a FIFO queue. Guarded by `stateQueue`.
    private var pendingWrites: [String: [(Result<Void, Error>) -> Void]] = [:]

    private var targetManufacturerData: Data?
    private var targetRssi: Int64?

    private func writeKey(_ deviceId: String, _ characteristicId: String)
        -> String
    {
        "\(deviceId)/\(characteristicId)"
    }

    init(flutterApi: QuickBlueFlutterApi) {
        self.flutterApi = flutterApi
        self.bluetoothStateListener = BluetoothStateListener()
        self.scanResultListener = ScanResultListener()
        self.l2CapSocketEventsListener = L2CapSocketEventsListener()

        super.init()
        bluetoothStateListener.currentStateProvider = { [weak self] in
            self?.getManager().state.platformBluetoothState ?? .unknown
        }
        discoveredPeripherals = Dictionary()
        streamDelegates = Dictionary()
        pendingServiceDiscovery = Dictionary()
    }

    func configure(configuration: PlatformDarwinConfiguration) throws {
        try stateQueue.sync {
            if manager != nil, configuration.maintainState != maintainState {
                throw PigeonError(
                    code: "InvalidState",
                    message:
                        "QuickBlue.configure(maintainState:) must be called before other Bluetooth APIs.",
                    details: nil
                )
            }
            maintainState = configuration.maintainState
        }

        if configuration.maintainState {
            _ = getManager()
        }
    }

    private func getManager() -> CBCentralManager {
        if let manager = manager {
            return manager
        }
        let options: [String: Any]? = maintainState
            ? [
                CBCentralManagerOptionRestoreIdentifierKey:
                    restorationIdentifier
            ]
            : nil
        let manager = CBCentralManager(delegate: self, queue: nil, options: options)
        self.manager = manager
        return manager
    }

    func isBluetoothAvailable() throws -> Bool {
        return getManager().state == .poweredOn
    }

    func startScan(
        serviceUuids: [String]?,
        manufacturerData: [Int64: FlutterStandardTypedData]?,
        rssi: Int64?,
        options: PlatformDarwinScanOptions?
    ) throws {
        let withServices: [CBUUID]?
        if let serviceUuids = serviceUuids, !serviceUuids.isEmpty {
            withServices = serviceUuids.map { uuid in CBUUID(string: uuid) }
        } else {
            withServices = nil
        }
        targetManufacturerData = nil
        targetRssi = rssi

        // Handle manufacturer data if provided
        if let manufacturerData = manufacturerData,
            !manufacturerData.isEmpty,
            let manufacturerId = manufacturerData.keys.first,
            let data = manufacturerData[manufacturerId]
        {
            var mByteArray = withUnsafeBytes(
                of: UInt16(manufacturerId).littleEndian
            ) { Array($0) }
            mByteArray.append(contentsOf: data.data)

            let givenManufacturerData = Data(_: mByteArray)
            targetManufacturerData = givenManufacturerData
        }

        let scanOptions =
            options
            ?? PlatformDarwinScanOptions(
                allowDuplicates: true,
                solicitedServiceUuids: []
            )
        var nativeOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: scanOptions
                .allowDuplicates
        ]
        if !scanOptions.solicitedServiceUuids.isEmpty {
            nativeOptions[
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey
            ] = scanOptions.solicitedServiceUuids.map { uuid in
                CBUUID(string: uuid)
            }
        }

        getManager().scanForPeripherals(
            withServices: withServices,
            options: nativeOptions
        )
    }

    func stopScan() throws {
        targetRssi = nil
        manager?.stopScan()
    }

    func connect(deviceId: String) throws {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            guard Self.claimConnection(deviceId, owner: connectionOwnerId) else {
                throw PigeonError(
                    code: "DeviceBusy",
                    message: "Another Flutter engine owns the connection to \(deviceId)",
                    details: nil
                )
            }
            // Prevent duplicate native connects while still completing a Dart
            // caller that asked for an already-established connection.
            if peripheral.state == .connected {
                flutterApi.onConnectionStateChange(
                    stateChange: PlatformConnectionStateChange(
                        deviceId: deviceId,
                        state: PlatformConnectionState.connected,
                        gattStatus: PlatformGattStatus.success
                    ),
                    completion: { _ in }
                )
                return
            }
            if peripheral.state == .connecting {
                return
            }
            peripheral.delegate = self
            getManager().connect(peripheral)
        }
    }

    func disconnect(deviceId: String) throws {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            cleanConnection(peripheral)
        }
    }

    func discoverServices(deviceId: String) throws {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            peripheral.discoverServices(nil)
        }
    }

    func setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: PlatformBleInputProperty
    ) throws {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            guard peripheral.getCharacteristic(characteristic, of: service) != nil
            else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown characteristic:\(characteristic)",
                    details: nil
                )
            }
            peripheral.setNotifiable(
                bleInputProperty,
                for: characteristic,
                of: service
            )
        }
    }

    func readValue(deviceId: String, service: String, characteristic: String)
        throws
    {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            guard
                let cbCharacteristic = peripheral.getCharacteristic(
                    characteristic,
                    of: service
                )
            else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown characteristic:\(characteristic)",
                    details: nil
                )
            }
            peripheral.readValue(for: cbCharacteristic)
        }
    }

    func writeValue(
        deviceId: String,
        service: String,
        characteristic: String,
        value: FlutterStandardTypedData,
        bleOutputProperty: PlatformBleOutputProperty,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let isWithResponse =
            bleOutputProperty != PlatformBleOutputProperty.withoutResponse
        do {
            try stateQueue.sync {
                guard let peripheral = discoveredPeripherals[deviceId] else {
                    throw PigeonError(
                        code: "IllegalArgument",
                        message: "Unknown deviceId:\(deviceId)",
                        details: nil
                    )
                }
                guard
                    let cbCharacteristic = peripheral.getCharacteristic(
                        characteristic,
                        of: service
                    )
                else {
                    throw PigeonError(
                        code: "IllegalArgument",
                        message: "Unknown characteristic:\(characteristic)",
                        details: nil
                    )
                }
                if isWithResponse {
                    // Resolved when didWriteValueFor fires for this write.
                    pendingWrites[
                        writeKey(deviceId, cbCharacteristic.uuid.uuidStr),
                        default: []
                    ].append(completion)
                }
                peripheral.writeValue(
                    value.data,
                    for: cbCharacteristic,
                    type: isWithResponse ? .withResponse : .withoutResponse
                )
            }
        } catch {
            completion(.failure(error))
            return
        }
        if !isWithResponse {
            // CoreBluetooth does not acknowledge writes without response, so the
            // call is complete once the value has been handed off.
            completion(.success(()))
        }
    }

    func requestMtu(deviceId: String, expectedMtu: Int64) throws -> Int64 {
        return try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            // CoreBluetooth negotiates the ATT MTU automatically at connection
            // time and offers no API to request a specific value, so
            // `expectedMtu` is ignored. `maximumWriteValueLength(for:)` reports
            // the largest single-packet payload (ATT_MTU - 3) for a
            // write-without-response; add the 3-byte ATT header back so the
            // returned value matches the ATT MTU other platforms report.
            let writeLength = peripheral.maximumWriteValueLength(
                for: .withoutResponse
            )
            return Int64(writeLength + 3)
        }
    }

    func openL2cap(
        deviceId: String,
        psm: Int64
    ) throws {
        try stateQueue.sync {
            guard let peripheral = discoveredPeripherals[deviceId] else {
                throw
                    PigeonError(
                        code: "IllegalArgument",
                        message: "Unknown deviceId:\(deviceId)",
                        details: nil
                    )
            }
            peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
        }
    }

    func closeL2cap(deviceId: String) throws {
        try stateQueue.sync {
            guard let streamDelegate = streamDelegates[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "No stream delegate for deviceId:\(deviceId)",
                    details: nil
                )
            }
            streamDelegate.close()
            streamDelegates.removeValue(forKey: deviceId)
        }
    }

    func writeL2cap(deviceId: String, value: FlutterStandardTypedData) throws {
        try stateQueue.sync {
            guard let streamDelegate = streamDelegates[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "No stream delegate for deviceId:\(deviceId)",
                    details: nil
                )
            }
            streamDelegate.write(data: value.data)
        }
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Stop scanning
        manager?.stopScan()
        bluetoothStateListener.onEventsDone()

        // Disconnect all active devices
        stateQueue.sync {
            for (_, peripheral) in discoveredPeripherals {
                cleanConnection(peripheral)
            }
        }
        isAttachedToEngine = false
        manager = nil
        Self.releaseConnections(owner: connectionOwnerId)
    }

    private func cleanConnection(_ peripheral: CBPeripheral) {
        if let delegate = streamDelegates[peripheral.identifier.uuidString] {
            delegate.close()
            streamDelegates.removeValue(forKey: peripheral.identifier.uuidString)
        }
        manager?.cancelPeripheralConnection(peripheral)
    }

    /// Fails any write-with-response completions still awaiting acknowledgement
    /// for `deviceId`; once the peripheral is gone CoreBluetooth never delivers
    /// didWriteValueFor, so the Dart futures would otherwise hang. Must be
    /// called outside a `stateQueue` block to avoid deadlock.
    private func failPendingWrites(forDeviceId deviceId: String, reason: String)
    {
        var completions: [(Result<Void, Error>) -> Void] = []
        stateQueue.sync {
            let prefix = "\(deviceId)/"
            // Snapshot keys before removing to avoid mutating during iteration.
            let matchingKeys = pendingWrites.keys.filter { $0.hasPrefix(prefix) }
            for key in matchingKeys {
                if let queue = pendingWrites.removeValue(forKey: key) {
                    completions.append(contentsOf: queue)
                }
            }
        }
        guard !completions.isEmpty else { return }
        let error = PigeonError(
            code: "Disconnected",
            message: reason,
            details: nil
        )
        for completion in completions {
            completion(.failure(error))
        }
    }
}

extension QuickBlueDarwinPlugin: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothStateListener.onEvent(event: central.state.platformBluetoothState)
    }

    public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let peripherals =
            dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]
            ?? []
        stateQueue.sync {
            for peripheral in peripherals {
                if peripheral.state != .disconnected,
                    !Self.claimConnection(
                        peripheral.identifier.uuidString,
                        owner: connectionOwnerId
                    )
                {
                    central.cancelPeripheralConnection(peripheral)
                    continue
                }
                peripheral.delegate = self
                discoveredPeripherals[peripheral.identifier.uuidString] =
                    peripheral
            }
        }

        for peripheral in peripherals {
            guard discoveredPeripherals[peripheral.identifier.uuidString] != nil
            else { continue }
            let state: PlatformConnectionState?
            switch peripheral.state {
            case .connected:
                state = .connected
            case .connecting:
                state = .connecting
            case .disconnecting:
                state = .disconnecting
            case .disconnected:
                state = .disconnected
            @unknown default:
                state = nil
            }
            guard let state = state else { continue }
            flutterApi.onConnectionStateChange(
                stateChange: PlatformConnectionStateChange(
                    deviceId: peripheral.identifier.uuidString,
                    state: state,
                    gattStatus: PlatformGattStatus.success
                ),
                completion: { _ in }
            )
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        stateQueue.sync {
            discoveredPeripherals[peripheral.identifier.uuidString] = peripheral
            if let targetRssi = targetRssi, RSSI.int64Value < targetRssi {
                return
            }

            let manufacturerData =
                advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let manufacturerDataPayload =
                manufacturerData.map { data in
                    data.count > 2 ? Data(data.dropFirst(2)) : Data()
                } ?? Data()
            let serviceUuids =
                advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
                ?? []
            let serviceData =
                advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
                ?? [:]
            let platformServiceData = Dictionary(
                uniqueKeysWithValues: serviceData.map {
                    (
                        $0.key.uuidStr,
                        FlutterStandardTypedData(bytes: $0.value)
                    )
                }
            )

            // When a manufacturer-data filter is active, only surface
            // peripherals whose advertised manufacturer data matches it.
            if let target = targetManufacturerData, target != manufacturerData {
                return
            }

            scanResultListener.onEvent(
                event: PlatformScanResult(
                    name: peripheral.name ?? "",
                    deviceId: peripheral.identifier.uuidString,
                    manufacturerDataHead: FlutterStandardTypedData(
                        bytes: manufacturerData ?? Data()
                    ),
                    manufacturerData: FlutterStandardTypedData(
                        bytes: manufacturerDataPayload
                    ),
                    rssi: Int64(truncating: RSSI),
                    serviceUuids: serviceUuids.map { $0.uuidStr },
                    serviceData: platformServiceData
                )
            )
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard Self.ownsConnection(
            peripheral.identifier.uuidString,
            owner: connectionOwnerId
        ), isAttachedToEngine else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        flutterApi.onConnectionStateChange(
            stateChange: PlatformConnectionStateChange(
                deviceId: peripheral.identifier.uuidString,
                state: PlatformConnectionState.connected,
                gattStatus: PlatformGattStatus.success
            ),
            completion: { _ in }
        )

    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard Self.releaseConnection(
            peripheral.identifier.uuidString,
            owner: connectionOwnerId
        ), isAttachedToEngine else { return }
        flutterApi.onConnectionStateChange(
            stateChange: PlatformConnectionStateChange(
                deviceId: peripheral.identifier.uuidString,
                state: PlatformConnectionState.disconnected,
                gattStatus: PlatformGattStatus.failure
            ),
            completion: { _ in }
        )
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let shouldEmit = Self.releaseConnection(
            peripheral.identifier.uuidString,
            owner: connectionOwnerId
        ) && isAttachedToEngine
        stateQueue.sync {
            if error != nil {
                central.cancelPeripheralConnection(peripheral)
                if let streamDelegate = streamDelegates[peripheral.identifier.uuidString]
                {
                    streamDelegate.close()
                }
            }
            if shouldEmit {
                flutterApi.onConnectionStateChange(
                    stateChange: PlatformConnectionStateChange(
                        deviceId: peripheral.identifier.uuidString,
                        state: PlatformConnectionState.disconnected,
                        gattStatus: error == nil
                            ? PlatformGattStatus.success : PlatformGattStatus.failure
                    ),
                    completion: { _ in }
                )
            }
        }

        failPendingWrites(
            forDeviceId: peripheral.identifier.uuidString,
            reason: "Peripheral disconnected before the write was acknowledged"
        )
    }
}

extension QuickBlueDarwinPlugin: CBPeripheralDelegate {
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        let deviceId = peripheral.identifier.uuidString
        guard error == nil, let services = peripheral.services else {
            pendingServiceDiscovery.removeValue(forKey: deviceId)
            flutterApi.onServiceDiscoveryComplete(
                deviceId: deviceId,
                completion: { _ in }
            )
            return
        }

        pendingServiceDiscovery[deviceId] = Set(
            services.map { $0.uuid.uuidStr }
        )
        if services.isEmpty {
            pendingServiceDiscovery.removeValue(forKey: deviceId)
            flutterApi.onServiceDiscoveryComplete(
                deviceId: deviceId,
                completion: { _ in }
            )
            return
        }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let deviceId = peripheral.identifier.uuidString
        flutterApi.onServiceDiscovered(
            serviceDiscovered: PlatformServiceDiscovered(
                deviceId: deviceId,
                serviceUuid: service.uuid.uuidStr,
                characteristics: (service.characteristics ?? []).map {
                    $0.platformCharacteristic
                }
            ),
            completion: { [weak self] _ in
                self?.pendingServiceDiscovery[deviceId]?.remove(
                    service.uuid.uuidStr
                )
                if self?.pendingServiceDiscovery[deviceId]?.isEmpty == true {
                    self?.pendingServiceDiscovery.removeValue(forKey: deviceId)
                    self?.flutterApi.onServiceDiscoveryComplete(
                        deviceId: deviceId,
                        completion: { _ in }
                    )
                }
            }
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Resolve the matching write-with-response completion. Extract it under
        // the lock, then invoke it outside to avoid reentrancy on stateQueue.
        let key = writeKey(
            peripheral.identifier.uuidString,
            characteristic.uuid.uuidStr
        )
        var completion: ((Result<Void, Error>) -> Void)?
        stateQueue.sync {
            if var queue = pendingWrites[key], !queue.isEmpty {
                completion = queue.removeFirst()
                if queue.isEmpty {
                    pendingWrites.removeValue(forKey: key)
                } else {
                    pendingWrites[key] = queue
                }
            }
        }
        if let error = error {
            NSLog(
                "[quick_blue] write failed for \(characteristic.uuid.uuidStr) on \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            )
            completion?(
                .failure(
                    PigeonError(
                        code: "WriteFailed",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            )
        } else {
            completion?(.success(()))
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            // A failed read/notify delivers no value, so the Dart-side read
            // would simply time out. Surface it for diagnosis.
            NSLog(
                "[quick_blue] value update failed for \(characteristic.uuid.uuidStr) on \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            )
            return
        }
        if let value = characteristic.value {
            flutterApi.onCharacteristicValueChanged(
                valueChanged: PlatformCharacteristicValueChanged(
                    deviceId: peripheral.identifier.uuidString,
                    serviceUuid: characteristic.service?.uuid.uuidStr ?? "",
                    characteristicId: characteristic.uuid.uuidStr,
                    value: FlutterStandardTypedData(bytes: value)
                ),
                completion: { _ in }
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // `setNotifiable` cannot fail synchronously on CoreBluetooth; a failure
        // to enable/disable notifications only arrives here. Log it so a
        // silently-broken subscription is diagnosable.
        if let error = error {
            NSLog(
                "[quick_blue] setNotifiable failed for \(characteristic.uuid.uuidStr) on \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didOpen channel: CBL2CAPChannel?,
        error: Error?
    ) {
        stateQueue.sync {
            guard let channel = channel else {
                return
            }

            let streamDelegate = L2CapStreamDelegate(
                channel: channel,
                onOpen: {
                    self.l2CapSocketEventsListener.onEvent(
                        event: PlatformL2CapSocketEvent(
                            deviceId: peripheral.identifier.uuidString,
                            opened: true
                        )
                    )
                },
                onData: {
                    data in
                    self.l2CapSocketEventsListener.onEvent(
                        event: PlatformL2CapSocketEvent(
                            deviceId: peripheral.identifier.uuidString,
                            data: FlutterStandardTypedData(bytes: data)
                        )
                    )
                },
                onClose: {
                    self.l2CapSocketEventsListener.onEvent(
                        event: PlatformL2CapSocketEvent(
                            deviceId: peripheral.identifier.uuidString,
                            closed: true
                        )
                    )
                },
                onError: { error in
                    self.l2CapSocketEventsListener.onEvent(
                        event: PlatformL2CapSocketEvent(
                            deviceId: peripheral.identifier.uuidString,
                            error: error?.localizedDescription
                        )
                    )

                }
            )
            streamDelegates[peripheral.identifier.uuidString] = streamDelegate
        }
    }
}

class L2CapStreamDelegate: NSObject, @preconcurrency StreamDelegate {
    // MARK: - Properties

    // Streams are non-optional and private for encapsulation.
    private let inputStream: InputStream
    private let outputStream: OutputStream

    // Keep a reference to the channel to manage its lifecycle.
    private var channel: CBL2CAPChannel?

    // Callbacks with clearer, more modern Swift naming.
    private let onOpen: () -> Void
    private let onData: (Data) -> Void
    private let onClose: () -> Void
    private let onError: (Error?) -> Void

    // MARK: - State
    private var openStreams = Set<Stream>()
    private var outgoingData = Data()
    private var hasNotifiedClose = false

    // MARK: - Performance Optimization
    // Allocate the read buffer once to avoid repeated memory allocation/deallocation.
    private let readBuffer: UnsafeMutablePointer<UInt8>
    private let bufferSize = 8192  // This can be tuned based on the L2CAP PSM's MTU.

    // MARK: - Initialization and Cleanup

    init(
        channel: CBL2CAPChannel,
        onOpen: @escaping () -> Void,
        onData: @escaping (Data) -> Void,
        onClose: @escaping () -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        self.channel = channel
        self.inputStream = channel.inputStream
        self.outputStream = channel.outputStream

        self.onOpen = onOpen
        self.onData = onData
        self.onClose = onClose
        self.onError = onError

        self.readBuffer = .allocate(capacity: bufferSize)

        super.init()

        setupStream(inputStream)
        setupStream(outputStream)
    }

    deinit {
        // Ensure the buffer is deallocated when this object is destroyed.
        readBuffer.deallocate()
        // The public close() method handles the rest of the cleanup.
    }

    private func setupStream(_ stream: Stream) {
        stream.delegate = self
        // All stream events will be handled on the main thread.
        stream.schedule(in: .main, forMode: .default)
        stream.open()
    }

    // MARK: - Public API

    /// Enqueues data to be sent over the L2CAP channel.
    public func write(data: Data) {
        // Ensure this operation is thread-safe by dispatching to the main actor.
        DispatchQueue.main.async {
            self.outgoingData.append(data)
            self.sendData()
        }
    }

    /// Closes the connection and cleans up all resources.
    public func close() {
        // This method is now the single entry point for a "clean" shutdown.
        DispatchQueue.main.async {
            self.handleClose()
        }
    }

    // MARK: - Stream Event Handling

    @MainActor
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            openStreams.insert(aStream)
            // When both streams are open, the channel is ready.
            if openStreams.count == 2 {
                onOpen()
            }
        case .hasBytesAvailable:
            readAvailableBytes()

        case .hasSpaceAvailable:
            sendData()

        case .errorOccurred:
            onError(aStream.streamError)
            // An error is a terminal event; close everything.
            handleClose()

        case .endEncountered:
            // If one stream ends, the channel is no longer usable.
            handleClose()

        default:
            #if DEBUG
                print("L2CAP Stream: Unhandled event \(eventCode)")
            #endif
        }
    }

    // MARK: - Private Helpers

    @MainActor
    private func readAvailableBytes() {
        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(readBuffer, maxLength: bufferSize)

            if bytesRead > 0 {
                // Create a Data object by copying the read bytes.
                let data = Data(bytes: readBuffer, count: bytesRead)
                onData(data)
            } else if bytesRead < 0, let error = inputStream.streamError {
                // Error occurred during read.
                onError(error)
                handleClose()
                break
            } else {
                // bytesRead == 0 indicates end of stream.
                break
            }
        }
    }

    @MainActor
    private func sendData() {
        // Ensure there is data to send and space in the output buffer.
        guard !outgoingData.isEmpty, outputStream.hasSpaceAvailable else {
            return
        }

        let bytesWritten = outgoingData.withUnsafeBytes {
            outputStream.write($0.baseAddress!, maxLength: outgoingData.count)
        }

        if bytesWritten > 0 {
            // Efficiently remove the data that was sent.
            outgoingData.removeFirst(bytesWritten)
        } else if bytesWritten < 0, let error = outputStream.streamError {
            // Error occurred during write.
            onError(error)
            handleClose()
        }
    }

    /// The single, unified method for closing streams and notifying the delegate.
    @MainActor
    private func handleClose() {
        // Ensure cleanup and notification happens only once.
        guard !hasNotifiedClose else { return }
        hasNotifiedClose = true

        inputStream.close()
        outputStream.close()

        inputStream.remove(from: .main, forMode: .default)
        outputStream.remove(from: .main, forMode: .default)

        inputStream.delegate = nil
        outputStream.delegate = nil

        // Release the reference to the channel, allowing it to be deallocated.
        channel = nil
        outgoingData.removeAll()

        onClose()
    }
}

class BluetoothStateListener: BluetoothStateStreamHandler {
    var eventSink: PigeonEventSink<PlatformBluetoothState>?
    var currentStateProvider: (() -> PlatformBluetoothState)?

    override func onListen(
        withArguments arguments: Any?,
        sink: PigeonEventSink<PlatformBluetoothState>
    ) {
        eventSink = sink
        if let currentStateProvider = currentStateProvider {
            sink.success(currentStateProvider())
        }
    }

    override func onCancel(withArguments arguments: Any?) {
        eventSink = nil
    }

    func onEvent(event: PlatformBluetoothState) {
        if let eventSink = eventSink {
            eventSink.success(event)
        }
    }

    func onEventsDone() {
        eventSink?.endOfStream()
        eventSink = nil
    }
}

class ScanResultListener: ScanResultsStreamHandler {
    var eventSink: PigeonEventSink<PlatformScanResult>?

    override func onListen(
        withArguments arguments: Any?,
        sink: PigeonEventSink<PlatformScanResult>
    ) {
        eventSink = sink
    }

    func onEvent(event: PlatformScanResult) {
        if let eventSink = eventSink {
            eventSink.success(event)
        }
    }

    func onEventsDone() {
        eventSink?.endOfStream()
        eventSink = nil
    }
}

class L2CapSocketEventsListener: L2CapSocketEventsStreamHandler {
    var eventSink: PigeonEventSink<PlatformL2CapSocketEvent>?

    override func onListen(
        withArguments arguments: Any?,
        sink: PigeonEventSink<PlatformL2CapSocketEvent>
    ) {
        eventSink = sink
    }

    func onEvent(event: PlatformL2CapSocketEvent) {
        if let eventSink = eventSink {
            eventSink.success(event)
        }
    }

    func onEventsDone() {
        eventSink?.endOfStream()
        eventSink = nil
    }
}
