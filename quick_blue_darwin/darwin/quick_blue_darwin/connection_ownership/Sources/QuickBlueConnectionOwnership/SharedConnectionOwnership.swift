import Foundation

/// Thread-safe ownership for connections shared by multiple plugin clients.
public final class SharedConnectionOwnership<
    DeviceID: Hashable,
    Client: AnyObject,
    NotificationKey: Hashable,
    NotificationProperty: Equatable
> {
    public struct Attachment {
        public let host: Client
        public let isNew: Bool
    }

    public struct DetachPlan {
        public let host: Client
        public let shouldDisconnect: Bool
        public let notificationsToDisable: [NotificationKey]
    }

    public enum NotificationClaimUpdate {
        case accepted(
            needsNativeWrite: Bool,
            previousProperty: NotificationProperty?
        )
        case conflicting
        case notAttached
    }

    private struct SharedConnection {
        let host: Client
        var clients: [ObjectIdentifier: Client]
        var notificationClaims:
            [NotificationKey: [ObjectIdentifier: NotificationProperty]] = [:]
    }

    private let lock = NSLock()
    private var connections: [DeviceID: SharedConnection] = [:]

    public init() {}

    public func attach(_ deviceId: DeviceID, client: Client) -> Attachment {
        withLock {
            let clientId = ObjectIdentifier(client)
            if var connection = connections[deviceId] {
                connection.clients[clientId] = client
                connections[deviceId] = connection
                return Attachment(host: connection.host, isNew: false)
            }
            connections[deviceId] = SharedConnection(
                host: client,
                clients: [clientId: client]
            )
            return Attachment(host: client, isNew: true)
        }
    }

    public func host(for deviceId: DeviceID, client: Client) -> Client? {
        withLock {
            guard
                let connection = connections[deviceId],
                connection.clients[ObjectIdentifier(client)] != nil
            else { return nil }
            return connection.host
        }
    }

    public func clients(for deviceId: DeviceID) -> [Client] {
        withLock {
            guard let connection = connections[deviceId] else { return [] }
            return Array(connection.clients.values)
        }
    }

    public func removeConnection(_ deviceId: DeviceID) -> [Client] {
        withLock {
            guard let connection = connections.removeValue(forKey: deviceId)
            else { return [] }
            return Array(connection.clients.values)
        }
    }

    public func detach(
        _ deviceId: DeviceID,
        client: Client,
        preserveFinalClient: Bool,
        preserveEmptyConnection: Bool = false
    ) -> DetachPlan? {
        withLock {
            let clientId = ObjectIdentifier(client)
            guard var connection = connections[deviceId],
                connection.clients[clientId] != nil
            else { return nil }

            var notificationsToDisable: [NotificationKey] = []
            for key in Array(connection.notificationClaims.keys) {
                guard var claims = connection.notificationClaims[key]
                else { continue }
                guard claims.removeValue(forKey: clientId) != nil else {
                    continue
                }
                if claims.isEmpty {
                    connection.notificationClaims.removeValue(forKey: key)
                    notificationsToDisable.append(key)
                } else {
                    connection.notificationClaims[key] = claims
                }
            }

            if connection.clients.count == 1, preserveFinalClient {
                connections[deviceId] = connection
                return DetachPlan(
                    host: connection.host,
                    shouldDisconnect: true,
                    notificationsToDisable: notificationsToDisable
                )
            }

            connection.clients.removeValue(forKey: clientId)
            if connection.clients.isEmpty {
                if preserveEmptyConnection {
                    connections[deviceId] = connection
                } else {
                    connections.removeValue(forKey: deviceId)
                }
            } else {
                connections[deviceId] = connection
            }
            return DetachPlan(
                host: connection.host,
                shouldDisconnect: connection.clients.isEmpty,
                notificationsToDisable: notificationsToDisable
            )
        }
    }

    public func takeUnclaimedConnection(
        _ deviceId: DeviceID,
        host: Client
    ) -> Bool {
        withLock {
            guard let connection = connections[deviceId],
                connection.host === host,
                connection.clients.isEmpty
            else { return false }
            connections.removeValue(forKey: deviceId)
            return true
        }
    }

    public func updateNotificationClaim(
        deviceId: DeviceID,
        key: NotificationKey,
        client: Client,
        property: NotificationProperty,
        disabledProperty: NotificationProperty
    ) -> NotificationClaimUpdate {
        withLock {
            let clientId = ObjectIdentifier(client)
            guard var connection = connections[deviceId],
                connection.clients[clientId] != nil
            else { return .notAttached }

            var claims = connection.notificationClaims[key] ?? [:]
            let previousProperty = claims[clientId]
            if property == disabledProperty {
                claims.removeValue(forKey: clientId)
                let needsNativeWrite = claims.isEmpty
                if claims.isEmpty {
                    connection.notificationClaims.removeValue(forKey: key)
                } else {
                    connection.notificationClaims[key] = claims
                }
                connections[deviceId] = connection
                return .accepted(
                    needsNativeWrite: needsNativeWrite,
                    previousProperty: previousProperty
                )
            }

            if let existing = claims.values.first, existing != property {
                return .conflicting
            }
            let needsNativeWrite = claims.isEmpty
            claims[clientId] = property
            connection.notificationClaims[key] = claims
            connections[deviceId] = connection
            return .accepted(
                needsNativeWrite: needsNativeWrite,
                previousProperty: previousProperty
            )
        }
    }

    public func restoreNotificationClaim(
        deviceId: DeviceID,
        key: NotificationKey,
        client: Client,
        property: NotificationProperty?
    ) {
        withLock {
            let clientId = ObjectIdentifier(client)
            guard var connection = connections[deviceId],
                connection.clients[clientId] != nil
            else { return }

            var claims = connection.notificationClaims[key] ?? [:]
            if let property {
                claims[clientId] = property
            } else {
                claims.removeValue(forKey: clientId)
            }
            if claims.isEmpty {
                connection.notificationClaims.removeValue(forKey: key)
            } else {
                connection.notificationClaims[key] = claims
            }
            connections[deviceId] = connection
        }
    }

    public func isHostingConnections(_ client: Client) -> Bool {
        withLock {
            connections.values.contains { $0.host === client }
        }
    }

    public func deviceIds(for client: Client) -> [DeviceID] {
        withLock {
            let clientId = ObjectIdentifier(client)
            return connections.compactMap { deviceId, connection in
                connection.clients[clientId] == nil ? nil : deviceId
            }
        }
    }

    private func withLock<T>(_ action: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }
}
