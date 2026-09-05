import Foundation

enum QuietHoursPolicy {
    static func isQuiet(
        at date: Date,
        startMinute: Int,
        endMinute: Int,
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = max(0, min(1_439, startMinute))
        let end = max(0, min(1_439, endMinute))
        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }
}
