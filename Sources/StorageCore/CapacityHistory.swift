import Foundation

public enum CapacityResolution: String, Codable, Sendable {
    case minute, hour, day, week, month
}

/// An observed range, never an estimate for time when the app was not running.
public struct CapacityPoint: Codable, Sendable, Identifiable {
    public var id: String { "\(volumeID)|\(resolution.rawValue)|\(bucket.timeIntervalSince1970)" }
    public let volumeID: String
    public let resolution: CapacityResolution
    public let bucket: Date
    public var firstDate: Date
    public var lastDate: Date
    public var count: Int
    public var averageAvailable: Double
    public var minimumAvailable: Int64
    public var maximumAvailable: Int64
    public var firstAvailable: Int64
    public var lastAvailable: Int64
    public var lastTotal: Int64

    public init(volume: Volume, date: Date = Date()) {
        volumeID = volume.id; resolution = .minute
        bucket = CapacityHistory.bucket(date, resolution: .minute)
        firstDate = date; lastDate = date; count = 1
        averageAvailable = Double(volume.available)
        minimumAvailable = volume.available; maximumAvailable = volume.available
        firstAvailable = volume.available; lastAvailable = volume.available; lastTotal = volume.total
    }

    fileprivate init(_ point: CapacityPoint, resolution: CapacityResolution) {
        self = CapacityPoint(volumeID: point.volumeID, resolution: resolution,
                             bucket: CapacityHistory.bucket(point.bucket, resolution: resolution),
                             firstDate: point.firstDate, lastDate: point.lastDate, count: point.count,
                             averageAvailable: point.averageAvailable, minimumAvailable: point.minimumAvailable,
                             maximumAvailable: point.maximumAvailable, firstAvailable: point.firstAvailable,
                             lastAvailable: point.lastAvailable, lastTotal: point.lastTotal)
    }
    private init(volumeID: String, resolution: CapacityResolution, bucket: Date, firstDate: Date, lastDate: Date,
                 count: Int, averageAvailable: Double, minimumAvailable: Int64, maximumAvailable: Int64,
                 firstAvailable: Int64, lastAvailable: Int64, lastTotal: Int64) {
        self.volumeID = volumeID; self.resolution = resolution; self.bucket = bucket
        self.firstDate = firstDate; self.lastDate = lastDate; self.count = count
        self.averageAvailable = averageAvailable; self.minimumAvailable = minimumAvailable
        self.maximumAvailable = maximumAvailable; self.firstAvailable = firstAvailable
        self.lastAvailable = lastAvailable; self.lastTotal = lastTotal
    }
    fileprivate mutating func merge(_ other: CapacityPoint) {
        let combined = count + other.count
        averageAvailable += (other.averageAvailable - averageAvailable) * Double(other.count) / Double(combined)
        count = combined
        minimumAvailable = min(minimumAvailable, other.minimumAvailable)
        maximumAvailable = max(maximumAvailable, other.maximumAvailable)
        if other.firstDate < firstDate { firstDate = other.firstDate; firstAvailable = other.firstAvailable }
        if other.lastDate >= lastDate { lastDate = other.lastDate; lastAvailable = other.lastAvailable; lastTotal = other.lastTotal }
    }
}

public enum CapacityHistory {
    // Fixed UTC buckets make retention independent of travel, DST, and locale changes.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    public static func bucket(_ date: Date, resolution: CapacityResolution) -> Date {
        let component: Calendar.Component
        switch resolution {
        case .minute: component = .minute
        case .hour: component = .hour
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        let start = calendar.dateInterval(of: component, for: date)!.start
        // Split weeks at month boundaries so later monthly compaction stays exact.
        return resolution == .week ? max(start, calendar.dateInterval(of: .month, for: date)!.start) : start
    }
    public static func aggregate(_ points: [CapacityPoint], resolution: CapacityResolution) -> [CapacityPoint] {
        var groups: [String: CapacityPoint] = [:]
        for point in points {
            let aggregate = CapacityPoint(point, resolution: resolution)
            if var existing = groups[aggregate.id] { existing.merge(aggregate); groups[aggregate.id] = existing }
            else { groups[aggregate.id] = aggregate }
        }
        return groups.values.sorted { $0.bucket == $1.bucket ? $0.volumeID < $1.volumeID : $0.bucket < $1.bucket }
    }
    public static func compact(_ points: [CapacityPoint], now: Date) -> [CapacityPoint] {
        let detailedCutoff = now.addingTimeInterval(-30 * 86400)
        let weeklyCutoff = calendar.date(byAdding: .month, value: -12, to: now)!
        var detail: [CapacityPoint] = [], weekly: [CapacityPoint] = [], monthly: [CapacityPoint] = []
        for point in points {
            if point.resolution == .month || point.lastDate < weeklyCutoff { monthly.append(point) }
            else if point.resolution == .week || point.lastDate < detailedCutoff { weekly.append(point) }
            else { detail.append(point) }
        }
        return (detail + aggregate(weekly, resolution: .week) + aggregate(monthly, resolution: .month))
            .sorted { $0.bucket < $1.bucket }
    }
}

public enum CapacityRange: String, CaseIterable, Sendable {
    case day = "24시간", month = "30일", year = "12개월", all = "전체"
    public var resolution: CapacityResolution {
        switch self { case .day: .hour; case .month: .day; case .year: .week; case .all: .month }
    }
    public func start(now: Date = Date()) -> Date {
        switch self {
        case .day: now.addingTimeInterval(-86400)
        case .month: now.addingTimeInterval(-30 * 86400)
        case .year: CapacityHistory.calendar.date(byAdding: .month, value: -12, to: now)!
        case .all: .distantPast
        }
    }
}
