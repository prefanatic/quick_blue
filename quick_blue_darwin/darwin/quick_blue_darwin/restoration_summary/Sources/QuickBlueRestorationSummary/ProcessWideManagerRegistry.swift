import Foundation

/// Thread-safe process-wide ownership for a native manager shared by multiple
/// plugin clients.
public final class ProcessWideManagerRegistry<
    Manager: AnyObject,
    Client: AnyObject,
    Configuration: Equatable,
    State,
    RestorationEvent
> {
    public struct Registration {
        public let currentState: State?
        public let restorationEvents: [RestorationEvent]
    }

    public struct ManagerAccess {
        public let manager: Manager
        public let configuration: Configuration
        public let wasCreated: Bool
    }

    private final class WeakClient {
        weak var value: Client?

        init(_ value: Client) {
            self.value = value
        }
    }

    private let lock = NSRecursiveLock()
    private let managerCreationLock = NSLock()
    private var manager: Manager?
    private var managerConfiguration: Configuration?
    private var clients: [ObjectIdentifier: WeakClient] = [:]
    private var activeClients: Set<ObjectIdentifier> = []
    private var currentState: State?
    private var restorationEvents: [RestorationEvent] = []

    public init() {}

    @discardableResult
    public func register(_ client: Client) -> Registration {
        withLock {
            pruneReleasedClients()
            clients[ObjectIdentifier(client)] = WeakClient(client)
            return Registration(
                currentState: currentState,
                restorationEvents: restorationEvents
            )
        }
    }

    /// Removes event and activity membership without destroying the shared
    /// manager. The manager can still be serving other engines or restoration.
    @discardableResult
    public func unregister(_ client: Client) -> Bool {
        withLock {
            let clientId = ObjectIdentifier(client)
            clients.removeValue(forKey: clientId)
            activeClients.remove(clientId)
            pruneReleasedClients()
            return !activeClients.isEmpty
        }
    }

    public func getOrCreateManager(
        for client: Client,
        configuration: Configuration,
        create: (Client) -> Manager
    ) -> ManagerAccess {
        managerCreationLock.lock()
        defer { managerCreationLock.unlock() }

        // Native initializers may synchronously invoke delegates that publish
        // through this registry, so never call the factory under `lock`.
        if let access = withLock({ () -> ManagerAccess? in
            if let manager = self.manager,
                let managerConfiguration = self.managerConfiguration
            {
                return ManagerAccess(
                    manager: manager,
                    configuration: managerConfiguration,
                    wasCreated: false
                )
            }
            return nil
        }) {
            return access
        }

        let manager = create(client)
        return withLock {
            self.manager = manager
            self.managerConfiguration = configuration
            return ManagerAccess(
                manager: manager,
                configuration: configuration,
                wasCreated: true
            )
        }
    }

    public var managerIfCreated: Manager? {
        withLock { manager }
    }

    public var configurationIfCreated: Configuration? {
        withLock { managerConfiguration }
    }

    public var registeredClientCount: Int {
        withLock {
            pruneReleasedClients()
            return clients.count
        }
    }

    public var firstRegisteredClient: Client? {
        withLock {
            pruneReleasedClients()
            return registeredClients().first
        }
    }

    /// Marks whether a client currently uses a process-wide activity such as a
    /// CoreBluetooth scan and returns whether any registered client still does.
    @discardableResult
    public func setActive(_ active: Bool, for client: Client) -> Bool {
        withLock {
            let clientId = ObjectIdentifier(client)
            if active, clients[clientId]?.value != nil {
                activeClients.insert(clientId)
            } else {
                activeClients.remove(clientId)
            }
            pruneReleasedClients()
            return !activeClients.isEmpty
        }
    }

    public func forEachActiveClient(_ notify: (Client) -> Void) {
        let snapshot = withLock {
            pruneReleasedClients()
            return activeClients.compactMap { clients[$0]?.value }
        }
        for client in snapshot {
            notify(client)
        }
    }

    public func publishState(
        _ state: State,
        notify: (Client, State) -> Void
    ) {
        let snapshot = withLock {
            currentState = state
            return registeredClients()
        }
        for client in snapshot {
            notify(client, state)
        }
    }

    public func publishRestorationEvent(
        _ event: RestorationEvent,
        notify: (Client, RestorationEvent) -> Void
    ) {
        let snapshot = withLock {
            restorationEvents.append(event)
            return registeredClients()
        }
        for client in snapshot {
            notify(client, event)
        }
    }

    /// Releases a non-restoring manager after the last engine unregisters.
    /// Restoring managers deliberately survive engine gaps for process-lifetime
    /// CoreBluetooth callbacks.
    public func resetIfUnused(where shouldReset: (Configuration) -> Bool) {
        managerCreationLock.lock()
        defer { managerCreationLock.unlock() }
        withLock {
            pruneReleasedClients()
            guard clients.isEmpty, let managerConfiguration,
                shouldReset(managerConfiguration)
            else { return }
            manager = nil
            self.managerConfiguration = nil
            activeClients.removeAll()
            currentState = nil
            restorationEvents.removeAll()
        }
    }

    private func registeredClients() -> [Client] {
        clients.values.compactMap(\.value)
    }

    private func pruneReleasedClients() {
        let releasedIds = clients.compactMap { clientId, client in
            client.value == nil ? clientId : nil
        }
        for clientId in releasedIds {
            clients.removeValue(forKey: clientId)
            activeClients.remove(clientId)
        }
    }

    private func withLock<T>(_ action: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }
}
