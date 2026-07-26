//
//  FoodRecordSchema.swift
//  FoodRecord 版本化 Schema 与 V2→V3 迁移计划
//
//  V2：rating: Int，无 iconImage
//  V3：rating: Double，含 iconImage: Data?
//

import Foundation
import SwiftData

enum FoodRecordSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [FoodRecordV2.self] }

    @Model
    final class FoodRecordV2 {
        @Attribute(.unique) var id: UUID
        var name: String
        var emoji: String
        var rating: Int
        var tagsRaw: String
        var remark: String
        var date: Date
        var categoryRaw: String
        var placeName: String?
        var address: String?
        var latitude: Double?
        var longitude: Double?

        init(id: UUID = UUID(), name: String, emoji: String = "🍽️",
             rating: Int = 4, tagsRaw: String = "", remark: String = "",
             date: Date = .init(), categoryRaw: String = "chinese",
             placeName: String? = nil, address: String? = nil,
             latitude: Double? = nil, longitude: Double? = nil) {
            self.id = id
            self.name = name
            self.emoji = emoji
            self.rating = rating
            self.tagsRaw = tagsRaw
            self.remark = remark
            self.date = date
            self.categoryRaw = categoryRaw
            self.placeName = placeName
            self.address = address
            self.latitude = latitude
            self.longitude = longitude
        }
    }
}

enum FoodRecordSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    // V3 使用主 FoodRecord.swift 里的当前类型
    static var models: [any PersistentModel.Type] { [FoodRecord.self] }
}

/// V2→V3 迁移计划。
/// SwiftData 对 rating Int→Double（同名字段类型变更）在实测中行为不稳定：
/// 部分场景下 Int 数据被读作 0.0。因此不依赖自动映射，而是清库 fallback
/// 在 App/PersonalButlerApp.swift 的 bootstrap 里处理。这里保留
/// MigrationPlan 结构，为未来的字段追加（无类型变更）留一个可扩展点。
enum FoodRecordMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FoodRecordSchemaV2.self, FoodRecordSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        // custom stage 里我们目前不做重映射（spec 明确"存量数据强转，不做重映射"）
        // 若 SwiftData 引擎无法完成 Int→Double 类型变更，会在 ModelContainer 初始化时抛错，
        // 由 bootstrap 中的 fallback 路径处理。
        [.custom(
            fromVersion: FoodRecordSchemaV2.self,
            toVersion: FoodRecordSchemaV3.self,
            willMigrate: nil,
            didMigrate: { _ in
                // 无重映射；rating 类型变更依赖 SwiftData 自动处理，
                // iconImage 保持默认 nil
            }
        )]
    }
}
