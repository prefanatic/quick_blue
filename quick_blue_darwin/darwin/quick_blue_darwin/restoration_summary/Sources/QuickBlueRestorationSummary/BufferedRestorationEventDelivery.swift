import Foundation

public final class BufferedRestorationEventDelivery<Event> {
    private let lock = NSRecursiveLock()
    private var delivery: ((Event) -> Void)?
    private var pendingEvents: [Event] = []

    public init() {}

    public func start(delivery: @escaping (Event) -> Void) {
        withLock {
            self.delivery = delivery
            let events = pendingEvents
            pendingEvents.removeAll()
            for event in events {
                delivery(event)
            }
        }
    }

    public func stop() {
        withLock {
            delivery = nil
        }
    }

    public func emit(_ event: Event) {
        withLock {
            guard let delivery = delivery else {
                pendingEvents.append(event)
                return
            }
            delivery(event)
        }
    }

    private func withLock<T>(_ action: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return action()
    }
}
