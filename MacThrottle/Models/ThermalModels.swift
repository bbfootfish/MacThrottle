import Foundation
import SwiftUI

enum ThermalPressure: String, Codable {
    case nominal
    case moderate
    case heavy
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .nominal: return "正常"
        case .moderate: return "中度"
        case .heavy: return "重度"
        case .critical: return "临界"
        case .unknown: return "未知"
        }
    }

    var isThrottling: Bool {
        switch self {
        case .heavy, .critical:
            return true
        default:
            return false
        }
    }

    var color: Color {
        switch self {
        case .nominal: return .green
        case .moderate: return .yellow
        case .heavy: return .orange
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}

struct HistoryEntry {
    let pressure: ThermalPressure
    let temperature: Double?
    let fanSpeed: Double?  // Percentage 0-100%
    let timestamp: Date
}
