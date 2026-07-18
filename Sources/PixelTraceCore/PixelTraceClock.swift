import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct PixelTraceTimestamp: Sendable, Equatable, Codable {
    public let wallClock: Date
    public let uptimeNanos: UInt64

    public init(wallClock: Date, uptimeNanos: UInt64) {
        self.wallClock = wallClock
        self.uptimeNanos = uptimeNanos
    }
}

public enum PixelTraceClock {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    public static func now() -> PixelTraceTimestamp {
        var timespec = timespec()
        clock_gettime(CLOCK_MONOTONIC_RAW, &timespec)
        let uptimeNanos = UInt64(timespec.tv_sec) * 1_000_000_000 + UInt64(timespec.tv_nsec)
        return PixelTraceTimestamp(wallClock: Date(), uptimeNanos: uptimeNanos)
    }

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
