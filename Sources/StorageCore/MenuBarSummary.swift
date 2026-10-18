import Foundation

public enum MenuBarDisplay: String, CaseIterable, Codable, Sendable {
    case available, used, percentage
    public var title: String {
        switch self {
        case .available: "여유 공간"
        case .used: "사용 공간"
        case .percentage: "사용률"
        }
    }
}
public enum MenuBarSummary {
    public static func label(volume: Volume?, display: MenuBarDisplay) -> String {
        guard let volume else { return "Storage —" }
        switch display {
        case .available: return Format.bytes(volume.available)
        case .used: return Format.bytes(volume.used)
        case .percentage: return String(format: "%.0f%%", min(100, max(0, Double(volume.used) / Double(max(1, volume.total)) * 100)))
        }
    }
    public static func isLow(volume: Volume?, warningGB: Int) -> Bool {
        guard let volume else { return false }
        return Double(volume.available) < Double(warningGB) * 1_073_741_824
    }
}
