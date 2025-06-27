import Foundation

public struct DateUtilities {
    
    public static let shared = DateUtilities()
    
    private init() {}
    
    public lazy var relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()
    
    public lazy var shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    public lazy var mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    
    public lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    public lazy var weekRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    public lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
    
    public lazy var monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
}

extension Calendar {
    
    public static let current = Calendar.current
    
    public func startOfWeek(for date: Date) -> Date {
        let interval = dateInterval(of: .weekOfYear, for: date)
        return interval?.start ?? date
    }
    
    public func endOfWeek(for date: Date) -> Date {
        let interval = dateInterval(of: .weekOfYear, for: date)
        return interval?.end?.addingTimeInterval(-1) ?? date
    }
    
    public func isInCurrentWeek(_ date: Date) -> Bool {
        return isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
    }
    
    public func isInCurrentMonth(_ date: Date) -> Bool {
        return isDate(date, equalTo: Date(), toGranularity: .month)
    }
    
    public func weekRange(for date: Date) -> String {
        let startOfWeek = self.startOfWeek(for: date)
        let endOfWeek = self.endOfWeek(for: date)
        
        let formatter = DateUtilities.shared.weekRangeFormatter
        let startString = formatter.string(from: startOfWeek)
        let endString = formatter.string(from: endOfWeek)
        
        return "\(startString) - \(endString)"
    }
    
    public func weeksBetween(_ startDate: Date, and endDate: Date) -> Int {
        let components = dateComponents([.weekOfYear], from: startDate, to: endDate)
        return components.weekOfYear ?? 0
    }
    
    public func daysBetween(_ startDate: Date, and endDate: Date) -> Int {
        let components = dateComponents([.day], from: startDate, to: endDate)
        return components.day ?? 0
    }
    
    public func previousWeek(from date: Date) -> Date {
        return self.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
    }
    
    public func nextWeek(from date: Date) -> Date {
        return self.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
    }
    
    public func weeksAgo(_ count: Int, from date: Date = Date()) -> Date {
        return self.date(byAdding: .weekOfYear, value: -count, to: date) ?? date
    }
    
    public func daysAgo(_ count: Int, from date: Date = Date()) -> Date {
        return self.date(byAdding: .day, value: -count, to: date) ?? date
    }
}

extension Date {
    
    public var startOfWeek: Date {
        return Calendar.current.startOfWeek(for: self)
    }
    
    public var endOfWeek: Date {
        return Calendar.current.endOfWeek(for: self)
    }
    
    public var startOfDay: Date {
        return Calendar.current.startOfDay(for: self)
    }
    
    public var endOfDay: Date {
        let startOfDay = self.startOfDay
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? self
    }
    
    public var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }
    
    public var endOfMonth: Date {
        let calendar = Calendar.current
        let startOfMonth = self.startOfMonth
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? self
    }
    
    public func isSameWeek(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, equalTo: otherDate, toGranularity: .weekOfYear)
    }
    
    public func isSameDay(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, equalTo: otherDate, toGranularity: .day)
    }
    
    public func isSameMonth(as otherDate: Date) -> Bool {
        return Calendar.current.isDate(self, equalTo: otherDate, toGranularity: .month)
    }
    
    public var isToday: Bool {
        return Calendar.current.isDateInToday(self)
    }
    
    public var isYesterday: Bool {
        return Calendar.current.isDateInYesterday(self)
    }
    
    public var isTomorrow: Bool {
        return Calendar.current.isDateInTomorrow(self)
    }
    
    public var isThisWeek: Bool {
        return Calendar.current.isInCurrentWeek(self)
    }
    
    public var isThisMonth: Bool {
        return Calendar.current.isInCurrentMonth(self)
    }
    
    public var weekRange: String {
        return Calendar.current.weekRange(for: self)
    }
    
    public var relativeString: String {
        return DateUtilities.shared.relativeDateFormatter.localizedString(for: self, relativeTo: Date())
    }
    
    public var shortString: String {
        return DateUtilities.shared.shortDateFormatter.string(from: self)
    }
    
    public var mediumString: String {
        return DateUtilities.shared.mediumDateFormatter.string(from: self)
    }
    
    public var timeString: String {
        return DateUtilities.shared.timeFormatter.string(from: self)
    }
    
    public var dayString: String {
        return DateUtilities.shared.dayFormatter.string(from: self)
    }
    
    public var monthYearString: String {
        return DateUtilities.shared.monthYearFormatter.string(from: self)
    }
    
    public func daysFromNow() -> Int {
        return Calendar.current.daysBetween(self, and: Date())
    }
    
    public func weeksFromNow() -> Int {
        return Calendar.current.weeksBetween(self, and: Date())
    }
}

extension TimeInterval {
    
    public var formattedDuration: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(self.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    public var formattedDurationShort: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
    
    public var formattedDurationMedium: String {
        let hours = Int(self / 3600)
        let minutes = Int((self.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours > 0 {
                return "\(days)d \(remainingHours)h"
            } else {
                return "\(days)d"
            }
        } else if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else if minutes > 0 {
            return "\(minutes) min"
        } else {
            return "< 1 min"
        }
    }
}

public struct WeekSelection {
    public let startDate: Date
    public let endDate: Date
    public let displayName: String
    public let isCurrentWeek: Bool
    
    public init(date: Date) {
        let calendar = Calendar.current
        self.startDate = calendar.startOfWeek(for: date)
        self.endDate = calendar.endOfWeek(for: date)
        self.displayName = calendar.weekRange(for: date)
        self.isCurrentWeek = calendar.isInCurrentWeek(date)
    }
    
    public static func currentWeek() -> WeekSelection {
        return WeekSelection(date: Date())
    }
    
    public static func previousWeek() -> WeekSelection {
        let previousWeek = Calendar.current.previousWeek(from: Date())
        return WeekSelection(date: previousWeek)
    }
    
    public static func weekContaining(_ date: Date) -> WeekSelection {
        return WeekSelection(date: date)
    }
    
    public func previous() -> WeekSelection {
        let previousWeek = Calendar.current.previousWeek(from: startDate)
        return WeekSelection(date: previousWeek)
    }
    
    public func next() -> WeekSelection {
        let nextWeek = Calendar.current.nextWeek(from: startDate)
        return WeekSelection(date: nextWeek)
    }
}

extension WeekSelection: Equatable {
    public static func == (lhs: WeekSelection, rhs: WeekSelection) -> Bool {
        return lhs.startDate.isSameWeek(as: rhs.startDate)
    }
}

extension WeekSelection: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(startDate.startOfWeek)
    }
}