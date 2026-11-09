import XCTest
import CoreBluetooth
import Flutter
import QuickBlueRestorationSummary
@testable import QuickBlueDarwinPluginTypeCheck

private final class Messenger: FlutterBinaryMessenger {}

private final class Registrar: FlutterPluginRegistrar {
    func messenger() -> FlutterBinaryMessenger { Messenger() }
    func publish(_ value: NSObject) {}
}

private final class RecordingPeripheral: CBPeripheral {
    var writes: [(Data, CBCharacteristicWriteType)] = []
    var acknowledgedLimit = 512
    var commandLimit = 97
    var commandSlots: Int?
    var characteristics: [CBCharacteristic] = []

    override func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
        type == .withResponse ? acknowledgedLimit : commandLimit
    }

    override func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType) {
        writes.append((data, type))
        characteristics.append(characteristic)
        if type == .withoutResponse, let slots = commandSlots {
            commandSlots = slots - 1
            canSendWriteWithoutResponse = slots > 1
        }
    }
}

private final class WriteFixture {
    let peripheral = RecordingPeripheral()
    let service = CBService()
    let characteristic = CBCharacteristic()
    let plugin: QuickBlueDarwinPlugin
    let manager: CBCentralManager
    var clients: [QuickBlueDarwinPlugin] = []

    var deviceId: String { peripheral.identifier.uuidString }

    init() throws {
        peripheral.state = .connected
        peripheral.canSendWriteWithoutResponse = false
        service.uuid = CBUUID(string: "180d")
        characteristic.uuid = CBUUID(string: "2a37")
        characteristic.properties = [.write, .writeWithoutResponse]
        characteristic.service = service
        service.characteristics = [characteristic]
        peripheral.services = [service]
        CBCentralManager.testPeripherals.append(peripheral)
        plugin = Self.makePlugin()
        try plugin.connect(deviceId: peripheral.identifier.uuidString)
        manager = try XCTUnwrap(CBCentralManager.testInstance)
        clients.append(plugin)
    }

    private static func makePlugin() -> QuickBlueDarwinPlugin {
        QuickBlueDarwinPlugin(
            flutterApi: QuickBlueFlutterApi(binaryMessenger: Messenger()),
            restorationBootstrapPolicy: CoreBluetoothRestorationBootstrapPolicy(persistentOptIn: false)
        )
    }

    func addClient() throws -> QuickBlueDarwinPlugin {
        let client = Self.makePlugin()
        try client.connect(deviceId: deviceId)
        clients.append(client)
        return client
    }

    func write(
        _ byte: UInt8,
        client: QuickBlueDarwinPlugin? = nil,
        characteristic: CBCharacteristic? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let target = characteristic ?? self.characteristic
        (client ?? plugin).writeValue(
            deviceId: deviceId,
            service: target.service!.uuid.uuidStr,
            characteristic: target.uuid.uuidStr,
            value: FlutterStandardTypedData(bytes: Data([byte])),
            bleOutputProperty: .withoutResponse,
            completion: completion
        )
    }

    func ready(slots: Int? = nil) {
        peripheral.commandSlots = slots
        peripheral.canSendWriteWithoutResponse = true
        peripheral.delegate?.peripheralIsReady(toSendWriteWithoutResponse: peripheral)
    }

    func disconnectRemotely() {
        peripheral.state = .disconnected
        manager.delegate?.centralManager(manager, didDisconnectPeripheral: peripheral, error: nil)
    }

    func close() {
        disconnectRemotely()
        for client in clients {
            client.detachFromEngine(for: Registrar())
        }
        CBCentralManager.testPeripherals.removeAll { $0 === peripheral }
    }
}

final class NativeWriteTests: XCTestCase {
    private func codes(_ results: [Result<Void, Error>]) -> [String] {
        results.map { result in
            switch result {
            case .success: return "success"
            case .failure(let error): return (error as? PigeonError)?.code ?? "unknown"
            }
        }
    }

    func testNativeLimitsBackpressureAndCompletion() throws {
        let peripheral = RecordingPeripheral()
        peripheral.state = .connected
        peripheral.canSendWriteWithoutResponse = true
        let service = CBService()
        service.uuid = CBUUID(string: "180d")
        let characteristic = CBCharacteristic()
        characteristic.uuid = CBUUID(string: "2a37")
        characteristic.properties = [.write, .writeWithoutResponse]
        characteristic.service = service
        service.characteristics = [characteristic]
        peripheral.services = [service]
        CBCentralManager.testPeripherals = [peripheral]
        defer { CBCentralManager.testPeripherals = [] }
        let plugin = QuickBlueDarwinPlugin(
            flutterApi: QuickBlueFlutterApi(binaryMessenger: Messenger()),
            restorationBootstrapPolicy: CoreBluetoothRestorationBootstrapPolicy(persistentOptIn: false)
        )
        let deviceId = peripheral.identifier.uuidString
        try plugin.connect(deviceId: deviceId)
        XCTAssertEqual(try plugin.maximumWriteValueLength(deviceId: deviceId, bleOutputProperty: .withResponse), 512)
        XCTAssertEqual(try plugin.maximumWriteValueLength(deviceId: deviceId, bleOutputProperty: .withoutResponse), 97)
        peripheral.commandLimit = 80
        XCTAssertEqual(try plugin.maximumWriteValueLength(deviceId: deviceId, bleOutputProperty: .withoutResponse), 80)

        func write(_ size: Int, _ mode: PlatformBleOutputProperty, _ completion: @escaping (Result<Void, Error>) -> Void) {
            plugin.writeValue(
                deviceId: deviceId, service: "180d", characteristic: "2a37",
                value: FlutterStandardTypedData(bytes: Data(repeating: 1, count: size)),
                bleOutputProperty: mode, completion: completion
            )
        }

        var commandCompletions = 0
        write(80, .withoutResponse) { result in
            if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
            commandCompletions += 1
        }
        XCTAssertEqual(commandCompletions, 1)
        XCTAssertEqual(peripheral.writes.count, 1)

        peripheral.canSendWriteWithoutResponse = false
        var blockedResults: [Result<Void, Error>] = []
        write(1, .withoutResponse) { result in
            blockedResults.append(result)
        }
        XCTAssertTrue(blockedResults.isEmpty)
        XCTAssertEqual(peripheral.writes.count, 1)

        var lengthError: String?
        write(81, .withoutResponse) { result in
            if case .failure(let error) = result { lengthError = (error as? PigeonError)?.code }
        }
        XCTAssertEqual(lengthError, "IllegalArgument")
        XCTAssertEqual(peripheral.writes.count, 1)

        var acknowledgedCompletions = 0
        write(512, .withResponse) { result in
            if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
            acknowledgedCompletions += 1
        }
        XCTAssertEqual(acknowledgedCompletions, 0)
        XCTAssertEqual(peripheral.writes.count, 2)
        peripheral.delegate?.peripheral(peripheral, didWriteValueFor: characteristic, error: nil)
        XCTAssertEqual(acknowledgedCompletions, 1)

        peripheral.canSendWriteWithoutResponse = true
        peripheral.delegate?.peripheralIsReady(toSendWriteWithoutResponse: peripheral)
        XCTAssertEqual(codes(blockedResults), ["success"])
        write(1, .withoutResponse) { result in
            if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
            commandCompletions += 1
        }
        XCTAssertEqual(commandCompletions, 2)
        XCTAssertEqual(peripheral.writes.count, 4)
        XCTAssertThrowsError(try plugin.maximumWriteValueLength(deviceId: UUID().uuidString, bleOutputProperty: .withResponse))
        peripheral.state = .disconnected
        let manager = try XCTUnwrap(CBCentralManager.testInstance)
        manager.delegate?.centralManager(manager, didDisconnectPeripheral: peripheral, error: nil)
        plugin.detachFromEngine(for: Registrar())
    }

    func testBlockedWriteWaitsForReadinessAndCompletesOnce() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(7) { results.append($0) }
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(fixture.peripheral.writes.isEmpty)
        fixture.peripheral.delegate?.peripheralIsReady(toSendWriteWithoutResponse: fixture.peripheral)
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(fixture.peripheral.writes.isEmpty)
        fixture.ready()
        fixture.ready()
        XCTAssertEqual(codes(results), ["success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([7])])
    }

    func testSharedQueuePreservesOrderAndChecksCapacityForEveryWrite() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        let peer = try fixture.addClient()
        let other = CBCharacteristic()
        other.uuid = CBUUID(string: "2a38")
        other.properties = [.writeWithoutResponse]
        other.service = fixture.service
        fixture.service.characteristics?.append(other)
        var completed: [UInt8] = []
        fixture.write(1) { result in
            XCTAssertEqual(self.codes([result]), ["success"])
            completed.append(1)
        }
        fixture.write(2, client: peer, characteristic: other) { result in
            XCTAssertEqual(self.codes([result]), ["success"])
            completed.append(2)
        }
        fixture.write(3) { result in
            XCTAssertEqual(self.codes([result]), ["success"])
            completed.append(3)
        }
        fixture.ready(slots: 1)
        XCTAssertEqual(completed, [1])
        fixture.ready(slots: 1)
        XCTAssertEqual(completed, [1, 2])
        fixture.ready(slots: 1)
        XCTAssertEqual(completed, [1, 2, 3])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([1]), Data([2]), Data([3])])
        XCTAssertTrue(fixture.peripheral.characteristics[0] === fixture.characteristic)
        XCTAssertTrue(fixture.peripheral.characteristics[1] === other)
        XCTAssertTrue(fixture.peripheral.characteristics[2] === fixture.characteristic)
    }

    func testReadinessDrainsAllWritesThatFit() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(1) { results.append($0) }
        fixture.write(2) { results.append($0) }
        fixture.ready()
        XCTAssertEqual(codes(results), ["success", "success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([1]), Data([2])])
    }

    func testPeripheralsHaveIndependentReadiness() throws {
        let first = try WriteFixture()
        defer { first.close() }
        let second = try WriteFixture()
        defer { second.close() }
        var firstResults: [Result<Void, Error>] = []
        var secondResults: [Result<Void, Error>] = []
        first.write(1) { firstResults.append($0) }
        second.write(2) { secondResults.append($0) }
        second.ready()
        XCTAssertTrue(firstResults.isEmpty)
        XCTAssertTrue(first.peripheral.writes.isEmpty)
        XCTAssertEqual(codes(secondResults), ["success"])
        first.ready()
        XCTAssertEqual(codes(firstResults), ["success"])
    }

    func testCompletionCanSubmitAnotherWrite() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(1) { result in
            results.append(result)
            fixture.write(2) { results.append($0) }
        }
        fixture.ready()
        XCTAssertEqual(codes(results), ["success", "success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([1]), Data([2])])
    }

    func testDisconnectRejectsQueuedWritesBeforeALateReadinessCallback() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(1) { results.append($0) }
        try fixture.plugin.disconnect(deviceId: fixture.deviceId)
        XCTAssertEqual(codes(results), ["Disconnected"])
        fixture.ready()
        XCTAssertEqual(codes(results), ["Disconnected"])
        XCTAssertTrue(fixture.peripheral.writes.isEmpty)
    }

    func testNativeDisconnectRejectsAllClientsAndDoesNotReplayAfterReconnect() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        let peer = try fixture.addClient()
        var results: [Result<Void, Error>] = []
        fixture.write(1) { results.append($0) }
        fixture.write(2, client: peer) { results.append($0) }
        fixture.disconnectRemotely()
        XCTAssertEqual(codes(results), ["Disconnected", "Disconnected"])
        fixture.peripheral.state = .connected
        try fixture.plugin.connect(deviceId: fixture.deviceId)
        fixture.write(3) { results.append($0) }
        fixture.ready()
        XCTAssertEqual(codes(results), ["Disconnected", "Disconnected", "success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([3])])
    }

    func testDisconnectCompletionCannotSubmitAnotherWrite() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(1) { result in
            results.append(result)
            fixture.write(2) { results.append($0) }
        }
        try fixture.plugin.disconnect(deviceId: fixture.deviceId)
        XCTAssertEqual(codes(results), ["Disconnected", "Disconnected"])
        fixture.ready()
        XCTAssertEqual(codes(results), ["Disconnected", "Disconnected"])
        XCTAssertTrue(fixture.peripheral.writes.isEmpty)
    }

    func testClientDisconnectPreservesTheOtherClientsQueuedWrites() throws {
        for disconnectHost in [false, true] {
            let fixture = try WriteFixture()
            defer { fixture.close() }
            let peer = try fixture.addClient()
            let departing = disconnectHost ? fixture.plugin : peer
            let remaining = disconnectHost ? peer : fixture.plugin
            var rejected: [Result<Void, Error>] = []
            var retained: [Result<Void, Error>] = []
            fixture.write(1, client: departing) { rejected.append($0) }
            fixture.write(2, client: remaining) { retained.append($0) }
            try departing.disconnect(deviceId: fixture.deviceId)
            XCTAssertEqual(codes(rejected), ["Disconnected"])
            XCTAssertTrue(retained.isEmpty)
            fixture.ready()
            XCTAssertEqual(codes(retained), ["success"])
            XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([2])])
        }
    }

    func testEngineDetachPreservesTheOtherClientsQueuedWrites() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        let peer = try fixture.addClient()
        var rejected: [Result<Void, Error>] = []
        var retained: [Result<Void, Error>] = []
        fixture.write(1) { rejected.append($0) }
        fixture.write(2, client: peer) { retained.append($0) }
        fixture.plugin.detachFromEngine(for: Registrar())
        XCTAssertEqual(codes(rejected), ["Disconnected"])
        fixture.ready()
        XCTAssertEqual(codes(retained), ["success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([2])])
    }

    func testServiceInvalidationRejectsOnlyAffectedWrites() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        let service = CBService()
        service.uuid = CBUUID(string: "180f")
        let characteristic = CBCharacteristic()
        characteristic.uuid = CBUUID(string: "2a19")
        characteristic.properties = [.writeWithoutResponse]
        characteristic.service = service
        service.characteristics = [characteristic]
        fixture.peripheral.services?.append(service)
        var rejected: [Result<Void, Error>] = []
        var retained: [Result<Void, Error>] = []
        fixture.write(1) { rejected.append($0) }
        fixture.write(2, characteristic: characteristic) { retained.append($0) }
        fixture.peripheral.delegate?.peripheral(fixture.peripheral, didModifyServices: [fixture.service])
        XCTAssertEqual(codes(rejected), ["InvalidState"])
        XCTAssertTrue(retained.isEmpty)
        fixture.ready()
        XCTAssertEqual(codes(rejected), ["InvalidState"])
        XCTAssertEqual(codes(retained), ["success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([2])])
    }

    func testRediscoveryCannotSubmitAnObsoleteCharacteristic() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        var results: [Result<Void, Error>] = []
        fixture.write(1) { results.append($0) }
        let replacement = CBCharacteristic()
        replacement.uuid = fixture.characteristic.uuid
        replacement.properties = fixture.characteristic.properties
        replacement.service = fixture.service
        fixture.service.characteristics = [replacement]
        fixture.write(2, characteristic: replacement) { results.append($0) }
        fixture.ready()
        XCTAssertEqual(codes(results), ["InvalidState", "success"])
        XCTAssertEqual(fixture.peripheral.writes.map { $0.0 }, [Data([2])])
        XCTAssertTrue(fixture.peripheral.characteristics[0] === replacement)
    }

    func testDisconnectedPeripheralRejectsNewWrites() throws {
        let fixture = try WriteFixture()
        defer { fixture.close() }
        fixture.peripheral.state = .disconnected
        var results: [Result<Void, Error>] = []
        fixture.write(1) { results.append($0) }
        fixture.ready()
        XCTAssertEqual(codes(results), ["Disconnected"])
        XCTAssertTrue(fixture.peripheral.writes.isEmpty)
    }
}
