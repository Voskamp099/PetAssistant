import Foundation

enum CalendarAuthState: String {
    case unknown, granted, denied
}

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool
    let notes: String?

    init(from ek: EKEventShim) {
        self.id = ek.id
        self.title = ek.title
        self.startDate = ek.startDate
        self.endDate = ek.endDate
        self.location = ek.location
        self.isAllDay = ek.isAllDay
        self.notes = ek.notes
    }

    var timeText: String {
        isAllDay ? "全天" : EventTimeFormat.range(from: startDate, to: endDate)
    }
}

/// 美式 12 小时显示；仅改变格式，仍使用用户所在时区。
enum EventTimeFormat {
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: date)
    }

    static func range(from start: Date, to end: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endDay = calendar.isDate(start, inSameDayAs: end) ? "" : "（\(day(end, timeZone: timeZone))）"
        return "\(time(start, timeZone: timeZone)) – \(endDay)\(time(end, timeZone: timeZone))"
    }

    private static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

/// 把 EventKit 的 EKEvent 包一层脱敏类型，避免把 EventKit 类型带过整个项目
struct EKEventShim {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let isAllDay: Bool
    let notes: String?
}

import EventKit
extension EKEventShim {
    init(from ek: EKEvent) {
        self.init(
            id: ek.eventIdentifier ?? UUID().uuidString,
            title: ek.title ?? "(无标题)",
            startDate: ek.startDate,
            endDate: ek.endDate,
            location: ek.location,
            isAllDay: ek.isAllDay,
            notes: ek.notes
        )
    }
}
extension CalendarEvent {
    init(from ek: EKEvent) {
        self.init(from: EKEventShim(from: ek))
    }
}
