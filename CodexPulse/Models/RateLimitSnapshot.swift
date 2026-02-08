import Foundation

enum RateLimitWindowKind: String, Codable, Hashable {
    case fiveHour
    case weekly
}

struct RateLimitSnapshot: Identifiable, Codable, Hashable {
    var id: String { "\(windowKind.rawValue)-\(windowMinutes)-\(capturedAt.timeIntervalSince1970)" }

    let windowKind: RateLimitWindowKind
    let usedPercent: Double
    let remainingPercent: Double
    let windowMinutes: Int
    let resetsAt: Date
    let capturedAt: Date
}

enum RateLimitFreshness: String {
    case fresh
    case stale
    case unavailable
}
