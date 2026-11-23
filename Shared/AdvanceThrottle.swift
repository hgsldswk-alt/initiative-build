import Foundation

struct AdvanceThrottle {
    private var last: TimeInterval?

    mutating func accept(_ uptime: TimeInterval) -> Bool {
        guard last.map({ uptime - $0 >= 0.35 }) ?? true else { return false }
        last = uptime
        return true
    }
}
