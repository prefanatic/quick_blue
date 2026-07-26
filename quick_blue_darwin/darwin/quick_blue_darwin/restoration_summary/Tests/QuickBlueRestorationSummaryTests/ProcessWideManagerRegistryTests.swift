import XCTest

@testable import QuickBlueRestorationSummary

final class ProcessWideManagerRegistryTests: XCTestCase {
    private final class FakeManager {}

    private final class FakeClient {
        var states: [Int] = []
        var restorationEvents: [String] = []
    }

    private typealias Registry = ProcessWideManagerRegistry<
        FakeManager,
        FakeClient,
        Bool,
        Int,
        String
    >

    func testTwoClientsCreateOnlyOneRestorationManager() {
        let registry = Registry()
        let first = FakeClient()
        let second = FakeClient()
        registry.register(first)
        registry.register(second)
        var creationCount = 0

        let firstAccess = registry.getOrCreateManager(
            for: first,
            configuration: true
        ) { _ in
            creationCount += 1
            return FakeManager()
        }
        let secondAccess = registry.getOrCreateManager(
            for: second,
            configuration: true
        ) { _ in
            creationCount += 1
            return FakeManager()
        }

        XCTAssertEqual(creationCount, 1)
        XCTAssertTrue(firstAccess.manager === secondAccess.manager)
        XCTAssertTrue(firstAccess.wasCreated)
        XCTAssertFalse(secondAccess.wasCreated)
    }

    func testBothClientsObserveCurrentStateAndLateClientGetsReplay() {
        let registry = Registry()
        let first = FakeClient()
        let second = FakeClient()
        registry.register(first)
        registry.register(second)

        registry.publishState(5) { client, state in
            client.states.append(state)
        }

        XCTAssertEqual(first.states, [5])
        XCTAssertEqual(second.states, [5])

        let lateClient = FakeClient()
        let registration = registry.register(lateClient)
        if let currentState = registration.currentState {
            lateClient.states.append(currentState)
        }
        XCTAssertEqual(lateClient.states, [5])
    }

    func testUnregisteringOneClientDoesNotTearDownSharedManager() {
        let registry = Registry()
        let first = FakeClient()
        let second = FakeClient()
        registry.register(first)
        registry.register(second)
        let manager = registry.getOrCreateManager(
            for: first,
            configuration: true
        ) { _ in FakeManager() }.manager

        registry.unregister(first)

        XCTAssertTrue(registry.managerIfCreated === manager)
        XCTAssertEqual(registry.registeredClientCount, 1)
        registry.publishState(5) { client, state in
            client.states.append(state)
        }
        XCTAssertTrue(first.states.isEmpty)
        XCTAssertEqual(second.states, [5])
    }

    func testUnregisteredClientCanDeallocateWhileManagerSurvives() {
        let registry = Registry()
        weak var releasedClient: FakeClient?

        autoreleasepool {
            let client = FakeClient()
            releasedClient = client
            registry.register(client)
            _ = registry.getOrCreateManager(
                for: client,
                configuration: true
            ) { _ in FakeManager() }
            registry.unregister(client)
        }

        XCTAssertNil(releasedClient)
        XCTAssertNotNil(registry.managerIfCreated)
    }

    func testRestorationCallbacksFanOutAndReplayToLateClient() {
        let registry = Registry()
        let first = FakeClient()
        let second = FakeClient()
        registry.register(first)
        registry.register(second)

        registry.publishRestorationEvent("restored") { client, event in
            client.restorationEvents.append(event)
        }

        XCTAssertEqual(first.restorationEvents, ["restored"])
        XCTAssertEqual(second.restorationEvents, ["restored"])

        let lateClient = FakeClient()
        let registration = registry.register(lateClient)
        lateClient.restorationEvents.append(
            contentsOf: registration.restorationEvents
        )
        XCTAssertEqual(lateClient.restorationEvents, ["restored"])
    }

    func testConcurrentManagerAccessCreatesOneManager() {
        let registry = Registry()
        let clients = (0..<20).map { _ in FakeClient() }
        for client in clients {
            registry.register(client)
        }
        let countLock = NSLock()
        var creationCount = 0

        DispatchQueue.concurrentPerform(iterations: clients.count) { index in
            _ = registry.getOrCreateManager(
                for: clients[index],
                configuration: true
            ) { _ in
                countLock.lock()
                creationCount += 1
                countLock.unlock()
                return FakeManager()
            }
        }

        XCTAssertEqual(creationCount, 1)
    }

    func testManagerCreationDoesNotBlockDelegateCallbacks() {
        let registry = Registry()
        let client = FakeClient()
        registry.register(client)
        let callbackCompleted = DispatchSemaphore(value: 0)

        _ = registry.getOrCreateManager(
            for: client,
            configuration: true
        ) { _ in
            DispatchQueue.global().async {
                registry.publishState(5) { client, state in
                    client.states.append(state)
                }
                callbackCompleted.signal()
            }
            XCTAssertEqual(
                callbackCompleted.wait(timeout: .now() + 2),
                .success
            )
            return FakeManager()
        }

        XCTAssertEqual(client.states, [5])
    }
}
