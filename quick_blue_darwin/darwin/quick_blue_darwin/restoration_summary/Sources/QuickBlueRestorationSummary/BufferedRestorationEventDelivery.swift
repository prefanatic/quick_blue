public final class BufferedRestorationEventDelivery<Event> {
    private var delivery: ((Event) -> Void)?
    private var pendingEvents: [Event] = []

    public init() {}

    public func start(delivery: @escaping (Event) -> Void) {
        self.delivery = delivery
        let events = pendingEvents
        pendingEvents.removeAll()
        for event in events {
            delivery(event)
        }
    }

    public func stop() {
        delivery = nil
    }

    public func emit(_ event: Event) {
        guard let delivery = delivery else {
            pendingEvents.append(event)
            return
        }
        delivery(event)
    }
}
