//
//  Date+Ext.swift
//

import Foundation

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var endOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: self) ?? self
    }

    func daysBetween(_ other: Date) -> Int {
        let a = Calendar.current.startOfDay(for: self)
        let b = Calendar.current.startOfDay(for: other)
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    var hourMinute: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: self)
    }
}
