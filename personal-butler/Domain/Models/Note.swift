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

    init(id: UUID = UUID(), title: String = "", content: String,
         tag: String = "灵感", createdAt: Date = .init(), updatedAt: Date = .init()) {
        self.id = id
        self.title = title
        self.content = content
        self.tag = tag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
