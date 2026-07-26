//
//  Note.swift
//

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var tag: String
    var createdAt: Date
    var updatedAt: Date
    /// 是否为首次安装时灌入的 Demo 数据；用户自添的为 false。
    var isDemo: Bool

    init(id: UUID = UUID(), title: String = "", content: String,
         tag: String = "灵感", createdAt: Date = .init(), updatedAt: Date = .init(),
         isDemo: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.tag = tag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDemo = isDemo
    }
}
