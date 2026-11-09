import Foundation

/// Dutch display strings for distances, heights and walking times.
public enum HikeFormat {
    public static func distance(_ metres: Double) -> String {
        if metres < 1000 {
            return "\(Int(metres.rounded())) m"
        }
        let kilometres = metres / 1000
        if kilometres >= 100 {
            return "\(Int(kilometres.rounded())) km"
        }
        return String(format: "%.1f", kilometres).replacingOccurrences(of: ".", with: ",") + " km"
    }

    public static func elevation(_ metres: Double) -> String {
        "\(Int(metres.rounded())) m"
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        // Round to five minutes: a walking-time estimate is not more precise than that.
        let totalMinutes = max(0, Int((seconds / 300).rounded()) * 5)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(max(minutes, 5)) min"
        }
        if minutes == 0 {
            return "\(hours) u"
        }
        return "\(hours) u \(minutes) min"
    }
}
