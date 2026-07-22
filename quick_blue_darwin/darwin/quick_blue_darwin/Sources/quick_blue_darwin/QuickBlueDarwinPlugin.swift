import CoreBluetooth
import Foundation

#if SWIFT_PACKAGE
    import QuickBlueConnectionOwnership
#endif

#if os(iOS)
    import Flutter
    import UIKit
    #if !targetEnvironment(macCatalyst)
        import AccessorySetupKit
    #endif
#elseif os(OSX)
    import FlutterMacOS
#endif

let GSS_SUFFIX = "0000-1000-8000-00805f9b34fb"

private func pigeonError(
    from error: Error,
    fallbackCode: String
) -> PigeonError {
    let nativeError = error as NSError
    return PigeonError(
        code: fallbackCode,
        message: nativeError.localizedDescription,
        details: [
            "domain": nativeError.domain,
            "code": nativeError.code,
        ]
    )
}

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

#if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 18.0, *)
    private final class AppleAccessorySetupCoordinator {
        typealias VoidCompletion = (Result<Void, Error>) -> Void

        private let session = ASAccessorySession()
        private var activated = false
        private var activationCompletions: [VoidCompletion] = []
        private var pickerCompletion:
            ((Result<PlatformAppleAccessory?, Error>) -> Void)?
        private var pickedAccessory: ASAccessory?

        init() {
            session.activate(on: .main) { [weak self] event in
                self?.handle(event)
            }
        }

        deinit {
            session.invalidate()
        }

        func showPicker(
            items: [PlatformAppleAccessoryPickerItem],
            completion: @escaping (Result<PlatformAppleAccessory?, Error>) -> Void
        ) {
            whenActivated { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success:
                    guard self.pickerCompletion == nil else {
                        completion(
                            .failure(
                                PigeonError(
                                    code: "InvalidState",
                                    message: "An AccessorySetupKit picker is already active.",
                                    details: nil
                                )
                            )
                        )
                        return
                    }

                    do {
                        let displayItems = try items.map(self.makeDisplayItem)
                        self.pickedAccessory = nil
                        self.pickerCompletion = completion
                        self.session.showPicker(for: displayItems) { [weak self] error in
                            guard let error = error else { return }
                            self?.finishPicker(.failure(error))
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }

        func accessories(
            completion: @escaping (Result<[PlatformAppleAccessory], Error>) -> Void
        ) {
            whenActivated { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success:
                    completion(
                        .success(
                            self.session.accessories.compactMap {
                                self.mapAccessory($0)
                            }
                        )
                    )
                }
            }
        }

        func remove(
            deviceId: String,
            completion: @escaping VoidCompletion
        ) {
            whenActivated { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                case .success:
                    guard
                        let accessory = self.session.accessories.first(where: {
                            $0.bluetoothIdentifier?.uuidString.caseInsensitiveCompare(
                                deviceId
                            ) == .orderedSame
                        })
                    else {
                        completion(
                            .failure(
                                PigeonError(
                                    code: "NotFound",
                                    message:
                                        "No AccessorySetupKit accessory has deviceId \(deviceId).",
                                    details: nil
                                )
                            )
                        )
                        return
                    }

                    self.session.removeAccessory(accessory) { error in
                        if let error = error {
                            completion(.failure(error))
                        } else {
                            completion(.success(()))
                        }
                    }
                }
            }
        }

        private func whenActivated(_ completion: @escaping VoidCompletion) {
            if activated {
                completion(.success(()))
            } else {
                activationCompletions.append(completion)
            }
        }

        private func handle(_ event: ASAccessoryEvent) {
            switch event.eventType {
            case .activated:
                activated = true
                let completions = activationCompletions
                activationCompletions.removeAll()
                completions.forEach { $0(.success(())) }
            case .invalidated:
                activated = false
                let error = event.error
                    ?? PigeonError(
                        code: "InvalidState",
                        message: "The AccessorySetupKit session was invalidated.",
                        details: nil
                    )
                let completions = activationCompletions
                activationCompletions.removeAll()
                completions.forEach { $0(.failure(error)) }
                finishPicker(.failure(error))
            case .accessoryAdded:
                pickedAccessory = event.accessory
            case .pickerDidDismiss:
                finishPicker(.success(pickedAccessory.flatMap(mapAccessory)))
            case .pickerSetupFailed:
                if let error = event.error {
                    finishPicker(.failure(error))
                }
            default:
                break
            }
        }

        private func finishPicker(
            _ result: Result<PlatformAppleAccessory?, Error>
        ) {
            guard let completion = pickerCompletion else { return }
            pickerCompletion = nil
            pickedAccessory = nil
            completion(result)
        }

        private func makeDisplayItem(
            _ item: PlatformAppleAccessoryPickerItem
        ) throws -> ASPickerDisplayItem {
            guard let productImage = UIImage(data: item.productImage.data) else {
                throw PigeonError(
                    code: "InvalidArgument",
                    message:
                        "Accessory productImage must contain UIImage-compatible encoded bytes.",
                    details: nil
                )
            }

            let discovery = item.discovery
            try validateInfoPlist(discovery)
            let descriptor = ASDiscoveryDescriptor()
            descriptor.bluetoothServiceUUID = CBUUID(
                string: discovery.serviceUuid
            )
            descriptor.bluetoothNameSubstring = discovery.nameSubstring
            descriptor.bluetoothServiceDataBlob = discovery.serviceData?.data
            descriptor.bluetoothServiceDataMask = discovery.serviceDataMask?.data
            descriptor.bluetoothRange = discovery.immediate ? .immediate : .default
            let displayItem = ASPickerDisplayItem(
                name: item.displayName,
                productImage: productImage,
                descriptor: descriptor
            )
            guard let migrationDeviceId = item.migrationDeviceId else {
                return displayItem
            }
            guard let peripheralIdentifier = UUID(uuidString: migrationDeviceId) else {
                throw PigeonError(
                    code: "InvalidArgument",
                    message:
                        "migrationDeviceId must be a CoreBluetooth peripheral UUID.",
                    details: migrationDeviceId
                )
            }
            let migrationItem = ASMigrationDisplayItem(
                name: item.displayName,
                productImage: productImage,
                descriptor: descriptor
            )
            migrationItem.peripheralIdentifier = peripheralIdentifier
            return migrationItem
        }

        private func validateInfoPlist(
            _ discovery: PlatformAppleAccessoryDiscovery
        ) throws {
            let supports =
                Bundle.main.object(forInfoDictionaryKey: "NSAccessorySetupSupports")
                as? [String] ?? []
            guard supports.contains(where: { $0.caseInsensitiveCompare("Bluetooth") == .orderedSame }) else {
                throw PigeonError(
                    code: "InvalidConfiguration",
                    message:
                        "Info.plist NSAccessorySetupSupports must contain Bluetooth.",
                    details: nil
                )
            }

            let declaredServices =
                Bundle.main.object(
                    forInfoDictionaryKey: "NSAccessorySetupBluetoothServices"
                ) as? [String] ?? []
            let serviceUuid = CBUUID(string: discovery.serviceUuid).uuidString
            guard declaredServices.contains(where: {
                CBUUID(string: $0).uuidString.caseInsensitiveCompare(serviceUuid)
                    == .orderedSame
            }) else {
                throw PigeonError(
                    code: "InvalidConfiguration",
                    message:
                        "Info.plist NSAccessorySetupBluetoothServices must contain \(discovery.serviceUuid).",
                    details: nil
                )
            }

            if let name = discovery.nameSubstring {
                let declaredNames =
                    Bundle.main.object(
                        forInfoDictionaryKey: "NSAccessorySetupBluetoothNames"
                    ) as? [String] ?? []
                guard declaredNames.contains(where: {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }) else {
                    throw PigeonError(
                        code: "InvalidConfiguration",
                        message:
                            "Info.plist NSAccessorySetupBluetoothNames must contain \(name).",
                        details: nil
                    )
                }
            }
        }

        private func mapAccessory(_ accessory: ASAccessory)
            -> PlatformAppleAccessory?
        {
            guard let identifier = accessory.bluetoothIdentifier else {
                return nil
            }
            return PlatformAppleAccessory(
                deviceId: identifier.uuidString,
                displayName: accessory.displayName
            )
        }
    }
#endif

public class QuickBlueDarwinPlugin: NSObject, FlutterPlugin, QuickBlueApi {
    private static let minimumReconnectInterval: TimeInterval = 0.1

    private struct NotificationKey: Hashable {
        let deviceId: String
        let service: String
        let characteristic: String
    }

    private typealias ConnectionOwnership = SharedConnectionOwnership<
        String,
        QuickBlueDarwinPlugin,
        NotificationKey,
        PlatformBleInputProperty
    >

    private struct PendingNotificationUpdate {
        let client: QuickBlueDarwinPlugin
        let previousProperty: PlatformBleInputProperty?
        let completion: (Result<Void, Error>) -> Void
    }

    private static let connectionOwnership = ConnectionOwnership()

    /// Attaches an engine and returns the process-wide CoreBluetooth host.
    private static func attachConnection(
        _ deviceId: String,
        client: QuickBlueDarwinPlugin
    ) -> (host: QuickBlueDarwinPlugin, isNew: Bool) {
        let attachment = connectionOwnership.attach(deviceId, client: client)
        return (attachment.host, attachment.isNew)
    }

    private static func host(
        for deviceId: String,
        client: QuickBlueDarwinPlugin
    ) -> QuickBlueDarwinPlugin? {
        connectionOwnership.host(for: deviceId, client: client)
    }

    private static func clients(for deviceId: String)
        -> [QuickBlueDarwinPlugin]
    {
        connectionOwnership.clients(for: deviceId)
    }

    private static func removeConnection(_ deviceId: String)
        -> [QuickBlueDarwinPlugin]
    {
        connectionOwnership.removeConnection(deviceId)
    }

    private static func detachConnection(
        _ deviceId: String,
        client: QuickBlueDarwinPlugin,
        preserveFinalClient: Bool,
        preserveEmptyConnection: Bool = false
    ) -> ConnectionOwnership.DetachPlan? {
        connectionOwnership.detach(
            deviceId,
            client: client,
            preserveFinalClient: preserveFinalClient,
            preserveEmptyConnection: preserveEmptyConnection
        )
    }

    /// Removes an engine-detach grace entry if no new engine attached before
    /// deferred physical cleanup runs.
    private static func takeUnclaimedConnection(
        _ deviceId: String,
        host: QuickBlueDarwinPlugin
    ) -> Bool {
        connectionOwnership.takeUnclaimedConnection(deviceId, host: host)
    }

    private static func updateNotificationClaim(
        key: NotificationKey,
        client: QuickBlueDarwinPlugin,
        property: PlatformBleInputProperty
    ) throws -> (
        needsNativeWrite: Bool,
        previousProperty: PlatformBleInputProperty?
    ) {
        switch connectionOwnership.updateNotificationClaim(
            deviceId: key.deviceId,
            key: key,
            client: client,
            property: property,
            disabledProperty: .disabled
        ) {
        case .notAttached:
            throw PigeonError(
                code: "IllegalArgument",
                message: "This Flutter engine is not connected to \(key.deviceId)",
                details: nil
            )
        case .conflicting:
            throw PigeonError(
                code: "InvalidState",
                message: "Another Flutter engine configured \(key.characteristic) differently",
                details: nil
            )
        case .accepted(let needsNativeWrite, let previousProperty):
            return (needsNativeWrite, previousProperty)
        }
    }

    private static func restoreNotificationClaim(
        key: NotificationKey,
        client: QuickBlueDarwinPlugin,
        property: PlatformBleInputProperty?
    ) {
        connectionOwnership.restoreNotificationClaim(
            deviceId: key.deviceId,
            key: key,
            client: client,
            property: property
        )
    }

    private static func isHostingConnections(_ client: QuickBlueDarwinPlugin)
        -> Bool
    {
        connectionOwnership.isHostingConnections(client)
    }

    private var isAttachedToEngine = true

    func getConnectedPeripherals(serviceUuids: [String]) throws -> [Peripheral] {
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
        #if os(iOS) && !targetEnvironment(macCatalyst)
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
        registrar.publish(instance)
    }

    private let stateQueue = DispatchQueue(label: "quick_blue.state.queue")

    private var flutterApi: QuickBlueFlutterApi
    private var bluetoothStateListener: BluetoothStateListener
    private var scanResultListener: ScanResultListener
    private var l2CapSocketEventsListener: L2CapSocketEventsListener

    private var manager: CBCentralManager?
    private var appleAccessorySetupCoordinator: AnyObject?
    private var maintainState = false
    private let restorationIdentifier =
        "\(Bundle.main.bundleIdentifier ?? "quick_blue").quick_blue.central"
    private var discoveredPeripherals: [String: CBPeripheral]!
    private var streamDelegates: [String: L2CapStreamDelegate]!
    private var pendingServiceDiscovery: [String: Set<String>]!

    // Completions awaiting CoreBluetooth characteristic callbacks, keyed by
    // "deviceId/characteristicId". CoreBluetooth serializes operations and
    // delivers callbacks in order, so each key holds a FIFO queue. Guarded by
    // `stateQueue`.
    private var pendingReads:
        [String: [(Result<FlutterStandardTypedData, Error>) -> Void]] = [:]
    private var pendingWrites: [String: [(Result<Void, Error>) -> Void]] = [:]
    private var pendingNotificationUpdates:
        [NotificationKey: [[PendingNotificationUpdate]]] = [:]
    private var pendingDisconnects: Set<String> = []
    private var lastDisconnectTimes: [String: TimeInterval] = [:]

    private var targetManufacturerData: Data?
    private var targetRssi: Int64?

    private func writeKey(_ deviceId: String, _ characteristicId: String)
        -> String
    {
        "\(deviceId)/\(characteristicId)"
    }

    private func withHostPeripheral<T>(
        _ deviceId: String,
        _ operation: (QuickBlueDarwinPlugin, CBPeripheral) throws -> T
    ) throws -> T {
        guard let host = Self.host(for: deviceId, client: self) else {
            throw PigeonError(
                code: "IllegalArgument",
                message: "This Flutter engine is not connected to \(deviceId)",
                details: nil
            )
        }
        return try host.stateQueue.sync {
            guard let peripheral = host.discoveredPeripherals[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            return try operation(host, peripheral)
        }
    }

    private func emitConnectionState(
        deviceId: String,
        state: PlatformConnectionState,
        status: PlatformGattStatus,
        error: Error? = nil
    ) {
        guard isAttachedToEngine else { return }
        let nativeError = error as NSError?
        flutterApi.onConnectionStateChange(
            stateChange: PlatformConnectionStateChange(
                deviceId: deviceId,
                state: state,
                gattStatus: status,
                errorDomain: nativeError?.domain,
                errorCode: nativeError.map { Int64($0.code) },
                errorMessage: nativeError?.localizedDescription
            ),
            completion: { _ in }
        )
    }

    private static func emitConnectionState(
        deviceId: String,
        state: PlatformConnectionState,
        status: PlatformGattStatus,
        error: Error? = nil
    ) {
        for client in clients(for: deviceId) {
            client.emitConnectionState(
                deviceId: deviceId,
                state: state,
                status: status,
                error: error
            )
        }
    }

    private func emitServiceDiscovered(_ service: PlatformServiceDiscovered) {
        guard isAttachedToEngine else { return }
        flutterApi.onServiceDiscovered(
            serviceDiscovered: service,
            completion: { _ in }
        )
    }

    private static func emitServiceDiscovered(
        deviceId: String,
        service: PlatformServiceDiscovered
    ) {
        for client in clients(for: deviceId) {
            client.emitServiceDiscovered(service)
        }
    }

    private func emitServiceDiscoveryComplete(deviceId: String) {
        guard isAttachedToEngine else { return }
        flutterApi.onServiceDiscoveryComplete(
            deviceId: deviceId,
            completion: { _ in }
        )
    }

    private static func emitServiceDiscoveryComplete(deviceId: String) {
        for client in clients(for: deviceId) {
            client.emitServiceDiscoveryComplete(deviceId: deviceId)
        }
    }

    private func emitCharacteristicValue(
        _ value: PlatformCharacteristicValueChanged
    ) {
        guard isAttachedToEngine else { return }
        flutterApi.onCharacteristicValueChanged(
            valueChanged: value,
            completion: { _ in }
        )
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

    func isAppleAccessorySetupSupported() throws -> Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 18.0, *) {
                return true
            }
        #endif
        return false
    }

    func showAppleAccessoryPicker(
        items: [PlatformAppleAccessoryPickerItem],
        completion: @escaping (Result<PlatformAppleAccessory?, Error>) -> Void
    ) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 18.0, *) {
                guard manager == nil else {
                    completion(
                        .failure(
                            PigeonError(
                                code: "InvalidState",
                                message:
                                    "AccessorySetupKit must run before Quick Blue initializes CoreBluetooth.",
                                details: nil
                            )
                        )
                    )
                    return
                }
                getAppleAccessorySetupCoordinator().showPicker(
                    items: items,
                    completion: completion
                )
                return
            }
        #endif
        completion(.failure(appleAccessorySetupUnsupportedError()))
    }

    func getAppleAccessories(
        completion: @escaping (Result<[PlatformAppleAccessory], Error>) -> Void
    ) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 18.0, *) {
                getAppleAccessorySetupCoordinator().accessories(
                    completion: completion
                )
                return
            }
        #endif
        completion(.failure(appleAccessorySetupUnsupportedError()))
    }

    func removeAppleAccessory(
        deviceId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        #if os(iOS)
            if #available(iOS 18.0, *) {
                getAppleAccessorySetupCoordinator().remove(
                    deviceId: deviceId,
                    completion: completion
                )
                return
            }
        #endif
        completion(.failure(appleAccessorySetupUnsupportedError()))
    }

    private func appleAccessorySetupUnsupportedError() -> PigeonError {
        PigeonError(
            code: "Unsupported",
            message:
                "Apple AccessorySetupKit requires iOS 18 or later and is unavailable on macOS.",
            details: nil
        )
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
        @available(iOS 18.0, *)
        private func getAppleAccessorySetupCoordinator()
            -> AppleAccessorySetupCoordinator
        {
            if let coordinator =
                appleAccessorySetupCoordinator
                as? AppleAccessorySetupCoordinator
            {
                return coordinator
            }
            let coordinator = AppleAccessorySetupCoordinator()
            appleAccessorySetupCoordinator = coordinator
            return coordinator
        }
    #endif

    private func getManager() -> CBCentralManager {
        if let manager = manager {
            return manager
        }
        let options: [String: Any]? =
            maintainState
            ? [
                CBCentralManagerOptionRestoreIdentifierKey:
                    restorationIdentifier
            ]
            : nil
        let manager = CBCentralManager(delegate: self, queue: nil, options: options)
        self.manager = manager
        return manager
    }

    /// Resolves a stable CoreBluetooth identifier without requiring this
    /// engine to scan or call getConnectedPeripherals first.
    private func retrieveKnownPeripheral(_ deviceId: String) -> CBPeripheral? {
        guard let identifier = UUID(uuidString: deviceId) else { return nil }
        guard
            let peripheral = getManager().retrievePeripherals(
                withIdentifiers: [identifier]
            ).first
        else { return nil }
        discoveredPeripherals[deviceId] = peripheral
        return peripheral
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
            let attachment = Self.attachConnection(deviceId, client: self)
            let host = attachment.host
            // Existing shared connections always resolve through their host.
            // A new host may recover a stable CoreBluetooth UUID directly so
            // callers do not need a racy connected-device lookup first.
            let sharedPeripheral =
                host.discoveredPeripherals[deviceId]
                ?? (attachment.isNew
                    ? host.retrieveKnownPeripheral(deviceId) : nil)
            guard let sharedPeripheral = sharedPeripheral else {
                _ = Self.detachConnection(
                    deviceId,
                    client: self,
                    preserveFinalClient: false
                )
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "Unknown deviceId:\(deviceId)",
                    details: nil
                )
            }
            if attachment.isNew {
                sharedPeripheral.delegate = host
            }
            // Prevent duplicate native connects while still completing a Dart
            // caller that asked for an already-established connection.
            if sharedPeripheral.state == .connected {
                emitConnectionState(
                    deviceId: deviceId,
                    state: .connected,
                    status: .success
                )
                return
            }
            if !attachment.isNew || sharedPeripheral.state == .connecting {
                return
            }
            let reconnectDelay = host.lastDisconnectTimes[deviceId].map {
                max(
                    0,
                    Self.minimumReconnectInterval
                        - (ProcessInfo.processInfo.systemUptime - $0)
                )
            } ?? 0
            if reconnectDelay > 0 {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + reconnectDelay
                ) { [weak self, weak host, weak sharedPeripheral] in
                    guard
                        let self,
                        let host,
                        let sharedPeripheral,
                        Self.host(for: deviceId, client: self) === host
                    else { return }
                    host.stateQueue.sync {
                        guard
                            !host.pendingDisconnects.contains(deviceId),
                            sharedPeripheral.state == .disconnected
                        else { return }
                        host.lastDisconnectTimes.removeValue(forKey: deviceId)
                        host.getManager().connect(sharedPeripheral)
                    }
                }
            } else {
                host.lastDisconnectTimes.removeValue(forKey: deviceId)
                host.getManager().connect(sharedPeripheral)
            }
        }
    }

    func disconnect(deviceId: String) throws {
        guard
            let plan = Self.detachConnection(
                deviceId,
                client: self,
                preserveFinalClient: true
            )
        else {
            throw PigeonError(
                code: "IllegalArgument",
                message: "This Flutter engine is not connected to \(deviceId)",
                details: nil
            )
        }
        try plan.host.disableNotifications(plan.notificationsToDisable)
        if plan.shouldDisconnect {
            try plan.host.stateQueue.sync {
                guard let peripheral = plan.host.discoveredPeripherals[deviceId]
                else {
                    throw PigeonError(
                        code: "IllegalArgument",
                        message: "Unknown deviceId:\(deviceId)",
                        details: nil
                    )
                }
                plan.host.cleanConnection(peripheral)
            }
        } else {
            emitConnectionState(
                deviceId: deviceId,
                state: .disconnected,
                status: .success
            )
        }
    }

    func discoverServices(deviceId: String) throws {
        try withHostPeripheral(deviceId) { _, peripheral in
            peripheral.discoverServices(nil)
        }
    }

    func setNotifiable(
        deviceId: String,
        service: String,
        characteristic: String,
        bleInputProperty: PlatformBleInputProperty,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var completesImmediately = false
        do {
            try withHostPeripheral(deviceId) { host, peripheral in
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
                let key = NotificationKey(
                    deviceId: deviceId,
                    service: cbCharacteristic.service?.uuid.uuidStr
                        ?? service.lowercased(),
                    characteristic: cbCharacteristic.uuid.uuidStr
                )
                let update = try Self.updateNotificationClaim(
                    key: key,
                    client: self,
                    property: bleInputProperty
                )
                let pending = PendingNotificationUpdate(
                    client: self,
                    previousProperty: update.previousProperty,
                    completion: completion
                )
                if update.needsNativeWrite {
                    host.pendingNotificationUpdates[key, default: []].append(
                        [pending]
                    )
                    peripheral.setNotifyValue(
                        bleInputProperty != .disabled,
                        for: cbCharacteristic
                    )
                } else if var batches = host.pendingNotificationUpdates[key],
                    !batches.isEmpty
                {
                    batches[batches.count - 1].append(pending)
                    host.pendingNotificationUpdates[key] = batches
                } else {
                    completesImmediately = true
                }
            }
        } catch {
            completion(.failure(error))
            return
        }
        if completesImmediately {
            completion(.success(()))
        }
    }

    func readValue(
        deviceId: String,
        service: String,
        characteristic: String,
        completion: @escaping (
            Result<FlutterStandardTypedData, Error>
        ) -> Void
    ) {
        do {
            try withHostPeripheral(deviceId) { host, peripheral in
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
                host.pendingReads[
                    host.writeKey(deviceId, cbCharacteristic.uuid.uuidStr),
                    default: []
                ].append(completion)
                peripheral.readValue(for: cbCharacteristic)
            }
        } catch {
            completion(.failure(error))
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
            try withHostPeripheral(deviceId) { host, peripheral in
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
                    host.pendingWrites[
                        host.writeKey(deviceId, cbCharacteristic.uuid.uuidStr),
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
        return try withHostPeripheral(deviceId) { _, peripheral in
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
        try withHostPeripheral(deviceId) { _, peripheral in
            peripheral.openL2CAPChannel(CBL2CAPPSM(psm))
        }
    }

    func closeL2cap(deviceId: String) throws {
        try withHostPeripheral(deviceId) { host, _ in
            guard let streamDelegate = host.streamDelegates[deviceId] else {
                throw PigeonError(
                    code: "IllegalArgument",
                    message: "No stream delegate for deviceId:\(deviceId)",
                    details: nil
                )
            }
            streamDelegate.close()
            host.streamDelegates.removeValue(forKey: deviceId)
        }
    }

    func writeL2cap(deviceId: String, value: FlutterStandardTypedData) throws {
        try withHostPeripheral(deviceId) { host, _ in
            guard let streamDelegate = host.streamDelegates[deviceId] else {
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
        manager?.stopScan()
        bluetoothStateListener.onEventsDone()

        isAttachedToEngine = false
        let deviceIds = Self.connectionDeviceIds(for: self)
        for deviceId in deviceIds {
            guard
                let plan = Self.detachConnection(
                    deviceId,
                    client: self,
                    preserveFinalClient: false,
                    preserveEmptyConnection: true
                )
            else { continue }
            do {
                try plan.host.disableNotifications(plan.notificationsToDisable)
            } catch {
                NSLog(
                    "[quick_blue] failed to disable notifications after engine detach: \(error.localizedDescription)"
                )
            }
            if plan.shouldDisconnect {
                // Give a concurrently-starting foreground engine one main-loop
                // turn to attach to the existing CoreBluetooth host. If it
                // does, attachConnection adds the new client and this cleanup
                // becomes a no-op.
                DispatchQueue.main.async {
                    guard
                        Self.takeUnclaimedConnection(
                            deviceId,
                            host: plan.host
                        )
                    else { return }
                    plan.host.stateQueue.sync {
                        if let peripheral = plan.host.discoveredPeripherals[deviceId] {
                            plan.host.cleanConnection(peripheral)
                        }
                    }
                    if !Self.isHostingConnections(plan.host) {
                        plan.host.manager = nil
                    }
                }
            }
        }
        if !Self.isHostingConnections(self) {
            manager = nil
        }
    }

    private static func connectionDeviceIds(
        for client: QuickBlueDarwinPlugin
    ) -> [String] {
        connectionOwnership.deviceIds(for: client)
    }

    private func disableNotifications(_ keys: [NotificationKey]) throws {
        for key in keys {
            try stateQueue.sync {
                guard
                    let peripheral = discoveredPeripherals[key.deviceId],
                    peripheral.getCharacteristic(
                        key.characteristic,
                        of: key.service
                    ) != nil
                else { return }
                peripheral.setNotifiable(
                    .disabled,
                    for: key.characteristic,
                    of: key.service
                )
            }
        }
    }

    private func cleanConnection(_ peripheral: CBPeripheral) {
        pendingDisconnects.insert(peripheral.identifier.uuidString)
        if let delegate = streamDelegates[peripheral.identifier.uuidString] {
            delegate.close()
            streamDelegates.removeValue(forKey: peripheral.identifier.uuidString)
        }
        manager?.cancelPeripheralConnection(peripheral)
        schedulePendingDisconnectCheck(peripheral)
    }

    /// CoreBluetooth can transition a cancelled connection attempt to
    /// `.disconnected` without delivering either terminal central-manager
    /// callback. Reconcile the observable state so the Dart disconnect future
    /// cannot remain pending, and reissue cancellation if a late connection
    /// wins the race.
    private func schedulePendingDisconnectCheck(
        _ peripheral: CBPeripheral,
        delayMilliseconds: Int = 50
    ) {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(delayMilliseconds)
        ) { [weak self, weak peripheral] in
            guard let self, let peripheral else { return }
            let deviceId = peripheral.identifier.uuidString
            let pending = self.stateQueue.sync {
                self.pendingDisconnects.contains(deviceId)
            }
            guard pending else { return }

            if peripheral.state == .disconnected {
                let clients = Self.removeConnection(deviceId)
                let shouldEmit = self.stateQueue.sync {
                    guard self.pendingDisconnects.remove(deviceId) != nil else {
                        return false
                    }
                    self.lastDisconnectTimes[deviceId] =
                        ProcessInfo.processInfo.systemUptime
                    return true
                }
                if shouldEmit {
                    for client in clients {
                        client.emitConnectionState(
                            deviceId: deviceId,
                            state: .disconnected,
                            status: .success
                        )
                    }
                    self.failPendingGattOperations(
                        forDeviceId: deviceId,
                        reason:
                            "Peripheral disconnected before the GATT operation completed"
                    )
                }
                return
            }

            self.manager?.cancelPeripheralConnection(peripheral)
            self.schedulePendingDisconnectCheck(
                peripheral,
                delayMilliseconds: min(delayMilliseconds * 2, 1_000)
            )
        }
    }

    /// Fails characteristic operations still awaiting callbacks for `deviceId`;
    /// once the peripheral is gone CoreBluetooth never delivers them, so the
    /// Dart futures would otherwise hang. Must be called outside a `stateQueue`
    /// block to avoid deadlock.
    private func failPendingGattOperations(
        forDeviceId deviceId: String,
        reason: String
    ) {
        var readCompletions:
            [(Result<FlutterStandardTypedData, Error>) -> Void] = []
        var writeCompletions: [(Result<Void, Error>) -> Void] = []
        var notificationCompletions: [(Result<Void, Error>) -> Void] = []
        stateQueue.sync {
            let prefix = "\(deviceId)/"
            // Snapshot keys before removing to avoid mutating during iteration.
            let matchingReadKeys = pendingReads.keys.filter {
                $0.hasPrefix(prefix)
            }
            for key in matchingReadKeys {
                if let queue = pendingReads.removeValue(forKey: key) {
                    readCompletions.append(contentsOf: queue)
                }
            }
            let matchingKeys = pendingWrites.keys.filter { $0.hasPrefix(prefix) }
            for key in matchingKeys {
                if let queue = pendingWrites.removeValue(forKey: key) {
                    writeCompletions.append(contentsOf: queue)
                }
            }
            let matchingNotificationKeys = pendingNotificationUpdates.keys
                .filter { $0.deviceId == deviceId }
            for key in matchingNotificationKeys {
                if let batches = pendingNotificationUpdates.removeValue(
                    forKey: key
                ) {
                    notificationCompletions.append(
                        contentsOf: batches.flatMap {
                            $0.map(\.completion)
                        }
                    )
                }
            }
        }
        guard !readCompletions.isEmpty || !writeCompletions.isEmpty
            || !notificationCompletions.isEmpty
        else {
            return
        }
        let error = PigeonError(
            code: "Disconnected",
            message: reason,
            details: nil
        )
        for completion in readCompletions {
            completion(.failure(error))
        }
        for completion in writeCompletions {
            completion(.failure(error))
        }
        for completion in notificationCompletions {
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
                if peripheral.state != .disconnected {
                    let attachment = Self.attachConnection(
                        peripheral.identifier.uuidString,
                        client: self
                    )
                    guard attachment.host === self else { continue }
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
            Self.emitConnectionState(
                deviceId: peripheral.identifier.uuidString,
                state: state,
                status: .success
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
        let deviceId = peripheral.identifier.uuidString
        let disconnectRequested = stateQueue.sync {
            pendingDisconnects.contains(deviceId)
        }
        if disconnectRequested {
            // CoreBluetooth can finish a connection after cancellation was
            // requested. Cancel again from the terminal connect callback so a
            // superseding Dart disconnect always receives a disconnect event.
            central.cancelPeripheralConnection(peripheral)
            return
        }
        Self.emitConnectionState(
            deviceId: deviceId,
            state: .connected,
            status: .success
        )

    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let deviceId = peripheral.identifier.uuidString
        let disconnectRequested = stateQueue.sync {
            let requested = pendingDisconnects.remove(deviceId) != nil
            lastDisconnectTimes[deviceId] = ProcessInfo.processInfo.systemUptime
            return requested
        }
        let clients = Self.removeConnection(deviceId)
        for client in clients {
            client.emitConnectionState(
                deviceId: deviceId,
                state: .disconnected,
                status: disconnectRequested ? .success : .failure,
                error: disconnectRequested ? nil : error
            )
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let deviceId = peripheral.identifier.uuidString
        let clients = Self.removeConnection(deviceId)
        stateQueue.sync {
            let disconnectRequested = pendingDisconnects.remove(deviceId) != nil
            lastDisconnectTimes[deviceId] = ProcessInfo.processInfo.systemUptime
            if error != nil, !disconnectRequested {
                central.cancelPeripheralConnection(peripheral)
                if let streamDelegate = streamDelegates[peripheral.identifier.uuidString] {
                    streamDelegate.close()
                }
            }
            for client in clients {
                client.emitConnectionState(
                    deviceId: deviceId,
                    state: .disconnected,
                    status: error == nil || disconnectRequested
                        ? .success : .failure,
                    error: disconnectRequested ? nil : error
                )
            }
        }

        failPendingGattOperations(
            forDeviceId: peripheral.identifier.uuidString,
            reason: "Peripheral disconnected before the GATT operation completed"
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
            Self.emitServiceDiscoveryComplete(deviceId: deviceId)
            return
        }

        pendingServiceDiscovery[deviceId] = Set(
            services.map { $0.uuid.uuidStr }
        )
        if services.isEmpty {
            pendingServiceDiscovery.removeValue(forKey: deviceId)
            Self.emitServiceDiscoveryComplete(deviceId: deviceId)
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
        Self.emitServiceDiscovered(
            deviceId: deviceId,
            service: PlatformServiceDiscovered(
                deviceId: deviceId,
                serviceUuid: service.uuid.uuidStr,
                characteristics: (service.characteristics ?? []).map {
                    $0.platformCharacteristic
                }
            )
        )
        pendingServiceDiscovery[deviceId]?.remove(service.uuid.uuidStr)
        if pendingServiceDiscovery[deviceId]?.isEmpty == true {
            pendingServiceDiscovery.removeValue(forKey: deviceId)
            Self.emitServiceDiscoveryComplete(deviceId: deviceId)
        }
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
                    pigeonError(from: error, fallbackCode: "WriteFailed")
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
        let key = writeKey(
            peripheral.identifier.uuidString,
            characteristic.uuid.uuidStr
        )
        var completion:
            ((Result<FlutterStandardTypedData, Error>) -> Void)?
        stateQueue.sync {
            if var queue = pendingReads[key], !queue.isEmpty {
                completion = queue.removeFirst()
                if queue.isEmpty {
                    pendingReads.removeValue(forKey: key)
                } else {
                    pendingReads[key] = queue
                }
            }
        }
        if let error = error {
            // A failed read/notify delivers no value, so the Dart-side read
            // would simply time out. Surface it for diagnosis.
            NSLog(
                "[quick_blue] value update failed for \(characteristic.uuid.uuidStr) on \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            )
            completion?(
                .failure(
                    pigeonError(from: error, fallbackCode: "ReadFailed")
                )
            )
            return
        }
        if let value = characteristic.value {
            completion?(
                .success(FlutterStandardTypedData(bytes: value))
            )
            let valueChanged = PlatformCharacteristicValueChanged(
                deviceId: peripheral.identifier.uuidString,
                serviceUuid: characteristic.service?.uuid.uuidStr ?? "",
                characteristicId: characteristic.uuid.uuidStr,
                value: FlutterStandardTypedData(bytes: value)
            )
            for client in Self.clients(for: peripheral.identifier.uuidString) {
                client.emitCharacteristicValue(valueChanged)
            }
        } else {
            completion?(
                .failure(
                    PigeonError(
                        code: "ReadFailed",
                        message: "CoreBluetooth returned no characteristic value",
                        details: nil
                    )
                )
            )
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let key = NotificationKey(
            deviceId: peripheral.identifier.uuidString,
            service: characteristic.service?.uuid.uuidStr ?? "",
            characteristic: characteristic.uuid.uuidStr
        )
        var pendingUpdates: [PendingNotificationUpdate] = []
        stateQueue.sync {
            if var batches = pendingNotificationUpdates[key],
                !batches.isEmpty
            {
                pendingUpdates = batches.removeFirst()
                if batches.isEmpty {
                    pendingNotificationUpdates.removeValue(forKey: key)
                } else {
                    pendingNotificationUpdates[key] = batches
                }
            }
        }
        if let error = error {
            NSLog(
                "[quick_blue] setNotifiable failed for \(characteristic.uuid.uuidStr) on \(peripheral.identifier.uuidString): \(error.localizedDescription)"
            )
            for update in pendingUpdates.reversed() {
                Self.restoreNotificationClaim(
                    key: key,
                    client: update.client,
                    property: update.previousProperty
                )
            }
            let mappedError = pigeonError(
                from: error,
                fallbackCode: "SetNotifiableFailed"
            )
            for update in pendingUpdates {
                update.completion(.failure(mappedError))
            }
        } else {
            for update in pendingUpdates {
                update.completion(.success(()))
            }
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
                    let event = PlatformL2CapSocketEvent(
                        deviceId: peripheral.identifier.uuidString,
                        opened: true
                    )
                    for client in Self.clients(for: peripheral.identifier.uuidString) {
                        client.l2CapSocketEventsListener.onEvent(event: event)
                    }
                },
                onData: {
                    data in
                    let event = PlatformL2CapSocketEvent(
                        deviceId: peripheral.identifier.uuidString,
                        data: FlutterStandardTypedData(bytes: data)
                    )
                    for client in Self.clients(for: peripheral.identifier.uuidString) {
                        client.l2CapSocketEventsListener.onEvent(event: event)
                    }
                },
                onClose: {
                    let event = PlatformL2CapSocketEvent(
                        deviceId: peripheral.identifier.uuidString,
                        closed: true
                    )
                    for client in Self.clients(for: peripheral.identifier.uuidString) {
                        client.l2CapSocketEventsListener.onEvent(event: event)
                    }
                },
                onError: { error in
                    let event = PlatformL2CapSocketEvent(
                        deviceId: peripheral.identifier.uuidString,
                        error: error?.localizedDescription
                    )
                    for client in Self.clients(for: peripheral.identifier.uuidString) {
                        client.l2CapSocketEventsListener.onEvent(event: event)
                    }

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
