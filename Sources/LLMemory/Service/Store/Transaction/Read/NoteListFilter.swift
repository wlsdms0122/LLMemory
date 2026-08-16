//
//  NoteListFilter.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NoteListFilter {
    // MARK: - Property
    var priority: String?
    var tags: [String]
    var fields: [NoteFieldFilter]
    var stale: Bool
    var sourceStale: Bool
    var limit: Int?

    // MARK: - Initializer
    init(
        priority: String? = nil,
        tags: [String] = [],
        fields: [NoteFieldFilter] = [],
        stale: Bool = false,
        sourceStale: Bool = false,
        limit: Int? = nil
    ) {
        self.priority = priority
        self.tags = tags
        self.fields = fields
        self.stale = stale
        self.sourceStale = sourceStale
        self.limit = limit
    }

    // MARK: - Public
    // MARK: - Private
}
