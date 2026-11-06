import Foundation

/// Notifiche Darwin tra app e tastiera, senza polling.
public final class DarwinNotifier: @unchecked Sendable {
    public static let shared = DarwinNotifier()

    private let lock = NSLock()
    private var handlers: [String: [@Sendable () -> Void]] = [:]

    private init() {}

    public static func post(_ signal: LoquiIPC.Signal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.rawValue as CFString),
            nil,
            nil,
            true
        )
    }

    /// `handler` viene chiamato su una coda del sistema.
    public func observe(_ signal: LoquiIPC.Signal, handler: @escaping @Sendable () -> Void) {
        let name = signal.rawValue
        let isFirst = lock.withLock {
            let isFirst = handlers[name] == nil
            handlers[name, default: []].append(handler)
            return isFirst
        }
        guard isFirst else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, name, _, _ in
                guard let name = name?.rawValue as String? else { return }
                DarwinNotifier.shared.fire(name)
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func fire(_ name: String) {
        let current = lock.withLock { handlers[name] ?? [] }
        for handler in current { handler() }
    }
}
