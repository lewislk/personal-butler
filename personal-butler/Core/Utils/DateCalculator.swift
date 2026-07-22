//
//  DateCalculator.swift
//  纪念日倒计时 / 农历工具
//

import Foundation

enum DateCalculator {
    /// 计算下一次每年重复日期距今天数
    static func daysUntilNextYearly(from date: Date, isLunar: Bool = false) -> Int {
        let now = Date()
        let cal = Calendar(identifier: isLunar ? .chinese : .gregorian)
        let today = Calendar.current.startOfDay(for: now)

        let comp = cal.dateComponents([.month, .day], from: date)
        var nextComp = comp
        let year = cal.component(.year, from: now)
        nextComp.year = year

        var next = cal.date(from: nextComp) ?? now
        if next < today {
            nextComp.year = year + 1
            next = cal.date(from: nextComp) ?? now
        }
        return today.daysBetween(next)
    }

    /// 计算起始日至今的累计天数（含今天）
    static func cumulativeDays(from start: Date) -> Int {
        let a = Calendar.current.startOfDay(for: start)
        let b = Calendar.current.startOfDay(for: Date())
        return (Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0) + 1
    }

    /// 格式化中文农历
    static func lunarString(from date: Date) -> String {
        // 年份用公历数字（用户直观熟悉），月/日用农历中文；chinese 日历的 `y`
        // 会输出 1~60 的循环年号，不适合直接展示。
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .chinese)
        f.dateFormat = "MMMMd日"
        return "农历 · \(year)年" + f.string(from: date)
    }

    static func gregorianDateLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return "公历 · " + f.string(from: date)
    }

    /// 相对时间标签（用于近期待办列表）
    static func relativeLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let days = cal.startOfDay(for: now).daysBetween(cal.startOfDay(for: date))
        let hm = date.hourMinute
        switch days {
        case 0: return "今天 \(hm)"
        case 1: return "明天 \(hm)"
        case 2...6:
            let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEEE"
            return "\(f.string(from: date)) \(hm)"
        default:
            return "\(days) 天后"
        }
    }
}
