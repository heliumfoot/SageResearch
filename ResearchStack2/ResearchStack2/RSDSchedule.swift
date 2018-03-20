//
//  RSDSchedule.swift
//  ResearchStack2
//
//  Copyright © 2018 Sage Bionetworks. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
// 1.  Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// 2.  Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation and/or
// other materials provided with the distribution.
//
// 3.  Neither the name of the copyright holder(s) nor the names of any contributors
// may be used to endorse or promote products derived from this software without
// specific prior written permission. No license is granted to the trademarks of
// the copyright holders even if such marks are included in this software.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import Foundation
import UserNotifications

/// The `RSDSchedule` protocol can be used to describe a local notification schedule. This provides a
/// shared interface for getting and setting the time of day and for setting up notifications.
public protocol RSDSchedule {
    
    /// The time of the day as a string with the format "HH:mm".
    var timeOfDayString: String? { get set }
    
    /// Get an array of the date components to use to set up notification triggers. This will return a
    /// `DateComponents` for each notification trigger that would be added to set notifications.
    ///
    /// - note: The date components will *not* include the user's current timezone.
    /// - returns: The date components to use to set up a trigger for each scheduling instance.
    func notificationTriggers() -> [DateComponents]
}

extension RSDSchedule {
    
    /// The time of the day as a date.
    public var timeOfDay: Date? {
        get {
            guard let tod = timeOfDayString else { return nil }
            return RSDDateCoderObject.hourAndMinutesOnly.inputFormatter.date(from: tod)
        }
        set {
            guard let tod = newValue else {
                timeOfDayString = nil
                return
            }
            timeOfDayString = RSDDateCoderObject.hourAndMinutesOnly.inputFormatter.string(from: tod)
        }
    }
    
    /// The time components using the ISO8601 calendar.
    public var timeComponents: DateComponents? {
        get {
            guard let tod = self.timeOfDay else { return nil }
            return Calendar.iso8601.dateComponents([.hour, .minute], from: tod)
        }
        set {
            guard let tod = newValue, let hour = tod.hour, let minute = tod.minute else {
                timeOfDayString = nil
                return
            }
            timeOfDayString = String(format: "%02d:%02d", hour, minute)
        }
    }
    
    /// Set the time by converting from Any.
    mutating public func setTime(from value: Any?) {
        if let dateValue = value as? Date {
            self.timeOfDay = dateValue
        } else if let dateComponents = value as? DateComponents {
            self.timeComponents = dateComponents
        } else {
            self.timeOfDayString = value as? String
        }
    }
}

/// A weekly schedule item is a light-weight codable struct that can be used to store and track events
/// that happen at regularily scheduled intervals. This schedule assumes a ISO8601 7-day calendar.
///
/// - example: `Codable` protocol schema.
/// ```
///    let json = """
///            {
///                "daysOfWeek": [1, 3, 5],
///                "timeOfDay": "08:00"
///            }
///            """.data(using: .utf8)! // our data in native (JSON) format
/// ```
public struct RSDWeeklyScheduleObject : Codable, RSDSchedule {
    
    private enum CodingKeys : String, CodingKey {
        case daysOfWeek, timeOfDayString = "timeOfDay"
    }
    
    /// The days of the week to include in the schedule. By default, this will be set to daily.
    public var daysOfWeek: Set<RSDWeekday> = RSDWeekday.all
    
    /// The time of the day as a string with the format "HH:mm".
    public var timeOfDayString: String?

    /// Is this a daily scheduled item?
    public var isDaily: Bool {
        return self.daysOfWeek == RSDWeekday.all
    }
    
    /// Get an array of the date components to use to set up notification triggers. This will return a
    /// `DateComponents` for each day of the week, unless the reminder should be posted daily.
    ///
    /// - note: The date components will *not* include the user's current timezone.
    /// - returns: The date components to use to set up a trigger for each scheduling instance.
    public func notificationTriggers() -> [DateComponents] {
        guard let timeComponents = self.timeComponents
            else {
                return []
        }
        
        if isDaily {
            // A daily scheduled trigger will include *only* the day and time.
            return [timeComponents]
        }
        else {
            // If this is scheduled for one or more days of the week then need to build a reminder for
            // each.
            return self.daysOfWeek.map {
                var dateComponents = timeComponents
                dateComponents.weekday = $0.rawValue
                return dateComponents
            }
        }
    }
    
    /// Set the weekdays by converting from Any array.
    mutating public func setWeekdays(from value: [Any]?) {
        if let weekdays = value as? Array<RSDWeekday> {
            self.daysOfWeek = Set(weekdays)
        } else if let weekdays = value as? Array<Int> {
            self.daysOfWeek = weekdays.rsd_mapAndFilterSet { RSDWeekday(rawValue: $0) }
        } else {
            self.daysOfWeek = RSDWeekday.all
        }
    }
    
    public init(timeOfDayString: String? = nil, daysOfWeek: Set<RSDWeekday> = RSDWeekday.all) {
        self.timeOfDayString = timeOfDayString
        self.daysOfWeek = daysOfWeek
    }
}

extension RSDWeeklyScheduleObject : Hashable, Comparable {
    
    public var hashValue: Int {
        return daysOfWeek.hashValue ^ RSDObjectHash(timeOfDayString)
    }
    
    public static func ==(lhs: RSDWeeklyScheduleObject, rhs: RSDWeeklyScheduleObject) -> Bool {
        return lhs.daysOfWeek == rhs.daysOfWeek && lhs.timeOfDayString == rhs.timeOfDayString
    }

    public static func <(lhs: RSDWeeklyScheduleObject, rhs: RSDWeeklyScheduleObject) -> Bool {
        guard let lTime = lhs.timeOfDayString else { return (rhs.timeOfDay != nil) }
        guard let rTime = rhs.timeOfDayString else { return false }
        return lTime < rTime
    }
}

/// `RSDWeeklyScheduleFormatter` can be used to display formatted text for a weekly schedule item.
public class RSDWeeklyScheduleFormatter : Formatter {
    
    /// The style of the display text for a weekly schedule item. 
    ///
    /// - example:
    ///     - long: "Thursday, Friday, and Saturday at 4:00 PM and 7:00 PM"
    ///     - medium: "4:00 PM, 7:30 PM\n Thursday, Friday, Saturday"
    ///     - short: "4:00 PM, 7:30 PM, Thu, Fri, Sat"
    public var style : DateFormatter.Style! {
        get { return _style }
        set { _style = newValue ?? .medium }
    }
    private var _style : DateFormatter.Style = .medium
    
    /// Formatted string for a weekly schedule item.
    public func string(from weeklySchedule: RSDWeeklyScheduleObject) -> String? {
        return string(from: [weeklySchedule])
    }
    
    /// Formatted string for an array of weekly schedule items.
    public func string(from weeklySchedules: [RSDWeeklyScheduleObject]) -> String? {
        let daysOfWeek = Set(weeklySchedules.map { $0.daysOfWeek })
        if daysOfWeek.count == 1 {
            let days = daysOfWeek.first!
            let daysString = _joinedDays(days, style: _style)
            let timesString = _joinedTimes(weeklySchedules)
            return _joinString(days: daysString, times: timesString, style: _style)
        } else {
            let formatterStyle = (_style == .medium) ? .short : _style
            let schedules = weeklySchedules.rsd_mapAndFilter { (item) -> String? in
                let daysString = _joinedDays(item.daysOfWeek, style: formatterStyle)
                let timesString = _joinedTimes([item])
                return _joinString(days: daysString, times: timesString, style: formatterStyle)
            }
            return schedules.joined(separator: "\n")
        }
    }
    
    /// Formatted string from a set of integers for each weekday.
    public func string(from days: Set<Int>) -> String? {
        let daysOfWeek = days.rsd_mapAndFilterSet { RSDWeekday(rawValue: $0) }
        return _joinedDays(daysOfWeek, style: _style)
    }
    
    private func _joinString(days: String?, times: String?, style: DateFormatter.Style) -> String? {
        if let days = days, let times = times {
            switch style {
            case .full, .long:
                return Localization.localizedStringWithFormatKey("SCHEDULE_FORMAT_%1$@_at_%2$@", days, times)
            case .medium, .none:
                return "\(times)\n\(days)"
            case .short:
                return "\(times), \(days)"
            }
        } else {
            return days ?? times
        }
    }
    
    private func _joinedDays(_ daysOfWeek: Set<RSDWeekday>, style: DateFormatter.Style) -> String? {
        guard daysOfWeek.count > 0 else {
            return nil
        }
        if daysOfWeek == RSDWeekday.all {
            return Localization.localizedString("SCHEDULE_EVERY_DAY")
        }
        switch style {
        case .full, .long:
            let days = daysOfWeek.sorted().map { $0.text! }
            return Localization.localizedAndJoin(days)
        case .medium, .none:
            let days = daysOfWeek.sorted().map { $0.text! }
            let delimiter = Localization.localizedString("LIST_FORMAT_DELIMITER")
            return days.joined(separator: delimiter)
        case .short:
            let days = daysOfWeek.sorted().map { $0.shortText! }
            let delimiter = Localization.localizedString("LIST_FORMAT_DELIMITER")
            return days.joined(separator: delimiter)
        }
    }
    
    private func _joinedTimes(_ weeklySchedules: [RSDWeeklyScheduleObject]) -> String? {
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let times = weeklySchedules.rsd_mapAndFilter {
            $0.timeOfDay != nil ? timeFormatter.string(from: $0.timeOfDay!) : nil
        }

        if _style == .full || _style == .long {
            return Localization.localizedAndJoin(times)
        } else {
            let delimiter = Localization.localizedString("LIST_FORMAT_DELIMITER")
            return times.joined(separator: delimiter)
        }
    }
    
    /// Override to provide generic formatter for formatting a string.
    override public func string(for obj: Any?) -> String? {
        if let schedules = obj as? [RSDWeeklyScheduleObject] {
            return self.string(from: schedules)
        } else if let schedule = obj as? RSDWeeklyScheduleObject {
            return self.string(from: schedule)
        } else if let days = obj as? Array<Int> {
            return self.string(from: Set(days))
        } else if let days = obj as? Set<Int> {
            return self.string(from: days)
        } else {
            return nil
        }
    }
}

/// The weekday enum assigns an enum value to each day of the week and implements `Comparable` to allow
/// for sorting the weekdays by the order appropriate for the user's current Locale.
public enum RSDWeekday : Int, Codable, RSDIntEnumSet {
    
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    /// Set of all the weekdays (Every day).
    public static var all: Set<RSDWeekday> {
        return Set(Array(1...7).map { RSDWeekday(rawValue: $0)! })
    }
    
    /// The localized weekday symbol.
    public var text: String? {
        let formatter = DateFormatter()
        return formatter.weekdaySymbols[self.rawValue - 1].capitalized
    }
    
    /// The short localized weekday symbol.
    public var shortText: String? {
        let formatter = DateFormatter()
        return formatter.shortWeekdaySymbols[self.rawValue - 1]
    }
}

extension RSDWeekday : Comparable {
    
    /// Sort the weekdays based on the `firstWeekday` property of the current Locale.
    public static func <(lhs: RSDWeekday, rhs: RSDWeekday) -> Bool {
        let firstWeekday = Locale.current.calendar.firstWeekday
        if (lhs.rawValue >= firstWeekday && rhs.rawValue >= firstWeekday) ||
           (lhs.rawValue < firstWeekday && rhs.rawValue < firstWeekday) {
            return lhs.rawValue < rhs.rawValue
        } else {
            return !(lhs.rawValue < firstWeekday && rhs.rawValue >= firstWeekday)
        }
    }
}

/// Extend the weekday enum to implement the choice and comparable protocols.
extension RSDWeekday : RSDChoice, RSDComparable {
    
    /// Returns `rawValue`.
    public var answerValue: Codable? {
        return self.rawValue
    }
    
    /// Returns `nil`.
    public var detail: String? {
        return nil
    }
    
    /// Returns `false`.
    public var isExclusive: Bool {
        return false
    }
    
    /// Returns `nil`.
    public var imageVendor: RSDImageVendor? {
        return nil
    }
    
    /// Returns `rawValue`.
    public var matchingAnswer: Any? {
        return self.rawValue
    }
}

extension RSDWeekday : RSDDocumentableIntEnum {
}

extension RSDWeeklyScheduleObject : RSDDocumentableCodableObject {
    
    static func codingKeys() -> [CodingKey] {
        return allCodingKeys()
    }
    
    private static func allCodingKeys() -> [CodingKeys] {
        let codingKeys: [CodingKeys] = [.daysOfWeek, .timeOfDayString]
        return codingKeys
    }
    
    static func validateAllKeysIncluded() -> Bool {
        let keys: [CodingKeys] = allCodingKeys()
        for (idx, key) in keys.enumerated() {
            switch key {
            case .daysOfWeek:
                if idx != 0 { return false }
            case .timeOfDayString:
                if idx != 1 { return false }
            }
        }
        return keys.count == 2
    }
    
    static func _examples() -> [RSDWeeklyScheduleObject] {
        let exampleA = RSDWeeklyScheduleObject()
        var exampleB = RSDWeeklyScheduleObject()
        exampleB.daysOfWeek = [.monday, .friday]
        exampleB.timeOfDayString = "08:20"
        return [exampleA, exampleB]
    }
    
    static func examples() -> [Encodable] {
        return _examples()
    }
}
