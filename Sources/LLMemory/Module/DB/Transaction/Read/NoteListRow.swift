//
//  NoteListRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct NoteListRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, title, summary, priority, stale
        case sourceStale = "source_stale"
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }

    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let priority: String
    public let stale: Bool
    public let sourceStale: Bool
    public let createdAt: Int
    public let editedAt: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
