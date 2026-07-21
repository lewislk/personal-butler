//
//  SeedData.swift
//  首次启动写入示例数据，让 UI 就绪
//

import Foundation
import SwiftData

enum SeedData {
    /// 判断是否已经初始化过；避免重复灌入
    static func ensureSeeded(in context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<AppModule>())
        guard (existing?.isEmpty ?? true) else { return }

        seedAppModules(context)
        seedSchedules(context)
        seedAnniversaries(context)
        seedPasswords(context)
        seedFoods(context)
        seedRecipes(context)
        seedNotes(context)
        seedOTP(context)
        seedSettings(context)

        try? context.save()
    }

    private static func seedAppModules(_ ctx: ModelContext) {
        let list: [AppModule] = [
            .init(id: "schedule",    name: "日程管理", tag: "计划 / 提醒",   iconSystemName: "calendar",              order: 0),
            .init(id: "anniversary", name: "纪念日",   tag: "生日 / 倒计时", iconSystemName: "heart",                 order: 1),
            .init(id: "password",    name: "密码记录", tag: "私密账号存储", iconSystemName: "lock.fill",             order: 2),
            .init(id: "food",        name: "美食记录", tag: "探店打卡相册", iconSystemName: "fork.knife",            order: 3),
            .init(id: "cook",        name: "烹饪管理", tag: "自建菜谱",     iconSystemName: "frying.pan",           order: 4),
            .init(id: "note",        name: "笔记",     tag: "灵感 / 摘录",   iconSystemName: "text.alignleft",        order: 5),
            .init(id: "ledger",      name: "记账本",   tag: "收支 / 预算",   iconSystemName: "yensign.circle",       order: 6, comingSoon: true),
            .init(id: "health",      name: "健康记录", tag: "运动 / 体检",   iconSystemName: "checkmark.circle",     order: 7, comingSoon: true),
            .init(id: "travel",      name: "旅行清单", tag: "行程 / 打包",   iconSystemName: "sun.max",              order: 8, comingSoon: true),
            .init(id: "movie",       name: "观影记录", tag: "电影 / 剧集",   iconSystemName: "play.rectangle",       order: 9, comingSoon: true),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedSchedules(_ ctx: ModelContext) {
        let cal = Calendar.current
        let today = Date()
        func at(_ h: Int, _ m: Int, day: Int = 0) -> Date {
            let base = cal.date(byAdding: .day, value: day, to: today) ?? today
            return cal.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
        }
        let list: [ScheduleEvent] = [
            .init(title: "团队晨会", remark: "同步本周迭代进度",
                  startDate: at(9, 0), reminderMinutesBefore: 15, colorTag: .blue),
            .init(title: "牙医预约", remark: "阳光医院 · 3号诊室",
                  startDate: at(14, 30), reminderMinutesBefore: 30, colorTag: .green),
            .init(title: "需求评审会议", remark: "与产品经理确认下一版需求",
                  startDate: at(18, 0), reminderMinutesBefore: 30, colorTag: .orange),
            .init(title: "江边跑步", remark: "30 分钟慢跑",
                  startDate: at(7, 0, day: 1), reminderMinutesBefore: 30, colorTag: .green),
            .init(title: "项目冲刺日", remark: "专注开发，不排会议",
                  startDate: at(9, 0, day: 1), isAllDay: true, colorTag: .blue),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedAnniversaries(_ ctx: ModelContext) {
        let cal = Calendar.current
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
        }
        let list: [Anniversary] = [
            .init(name: "妈妈生日", date: date(1970, 7, 23), type: .yearly, emoji: "🎂"),
            .init(name: "结婚周年", date: date(2018, 8, 17), type: .yearly, emoji: "💍"),
            .init(name: "爸爸生日", date: date(1968, 10, 8), isLunar: true, type: .yearly, emoji: "🎉"),
            .init(name: "中秋节",   date: date(2026, 9, 25), isLunar: true, type: .yearly, emoji: "🌕"),
            .init(name: "入职纪念", date: date(2022, 3, 14), type: .cumulative, emoji: "💼"),
            .init(name: "与她在一起", date: date(2020, 11, 2), type: .cumulative, emoji: "❤️"),
            .init(name: "戒烟",     date: date(2025, 1, 1),  type: .cumulative, emoji: "🚭"),
            .init(name: "开始学 SwiftUI", date: date(2026, 5, 10), type: .cumulative, emoji: "📱"),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedPasswords(_ ctx: ModelContext) {
        struct P { let platform: String; let account: String; let pwd: String; let cate: PasswordCategory; let type: String }
        let seeds: [P] = [
            .init(platform: "微信",     account: "lewis_88@qq.com",     pwd: "Weixin@2026",     cate: .social,  type: "社交 · 常用"),
            .init(platform: "招商银行", account: "6225 **** **** 8823", pwd: "Bank@Cmb886",     cate: .finance, type: "金融"),
            .init(platform: "飞书办公", account: "lewis@company.com",   pwd: "Feishu@Work123",  cate: .office,  type: "办公"),
        ]
        for s in seeds {
            let key = "pwd." + UUID().uuidString
            KeychainManager.save(s.pwd, for: key)
            let acc = PasswordAccount(platform: s.platform, account: s.account,
                                      typeText: s.type, category: s.cate,
                                      passwordKeychainKey: key)
            ctx.insert(acc)
        }
    }

    private static func seedFoods(_ ctx: ModelContext) {
        let list: [FoodRecord] = [
            .init(name: "兰州牛肉面", emoji: "🍜", rating: 4,
                  tags: ["中餐", "午餐"], remark: "牛肉给得多，汤头清亮，会再来", category: .chinese),
            .init(name: "Sushi 舞 · 日料", emoji: "🍣", rating: 5,
                  tags: ["日料", "晚餐", "约会"], remark: "环境安静，三文鱼刺身很新鲜", category: .japanese),
            .init(name: "喜茶 · 芝芝莓莓", emoji: "🧋", rating: 4,
                  tags: ["奶茶", "下午茶"], remark: "莓果酸甜适口，甜度七分刚好", category: .milktea),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedRecipes(_ ctx: ModelContext) {
        let list: [CookRecipe] = [
            .init(name: "番茄鸡蛋面", emoji: "🍅", difficulty: .easy,   minutes: 20, category: .noodle,
                  ingredients: "面条 200g\n番茄 2 个\n鸡蛋 2 枚",
                  steps: "1. 番茄去皮切块\n2. 鸡蛋炒散\n3. 加水煮面 10 分钟"),
            .init(name: "蒜蓉炒时蔬", emoji: "🥬", difficulty: .easy,   minutes: 10, category: .home),
            .init(name: "红烧肉",     emoji: "🍖", difficulty: .medium, minutes: 90, category: .home),
            .init(name: "舒芙蕾松饼", emoji: "🍰", difficulty: .hard,   minutes: 40, category: .dessert),
            .init(name: "日式豚骨拉面", emoji: "🍜", difficulty: .hard, minutes: 120, category: .noodle),
            .init(name: "冬瓜排骨汤", emoji: "🍲", difficulty: .easy,   minutes: 60, category: .soup),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedNotes(_ ctx: ModelContext) {
        let list: [Note] = [
            .init(content: "主页需要做「今日待办 / 近期待办」的分段切换……",
                  tag: "灵感"),
            .init(content: "「简单是最终极的复杂」— 达芬奇",
                  tag: "摘录"),
        ]
        list.forEach { ctx.insert($0) }
    }

    private static func seedOTP(_ ctx: ModelContext) {
        // 示例 TOTP：Base32 密钥
        let seeds: [(String, String, String)] = [
            ("GitHub", "lewis@github.com", "JBSWY3DPEHPK3PXP"),
            ("Google", "lewis.lau@gmail.com", "GEZDGNBVGY3TQOJQ"),
        ]
        for (issuer, name, secret) in seeds {
            let key = "otp." + UUID().uuidString
            KeychainManager.save(secret, for: key)
            let acc = OTPAccount(issuer: issuer, accountName: name,
                                 secretKeychainKey: key)
            ctx.insert(acc)
        }
    }

    private static func seedSettings(_ ctx: ModelContext) {
        ctx.insert(AppSetting())
    }
}
