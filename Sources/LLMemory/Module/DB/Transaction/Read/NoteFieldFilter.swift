//
//  NoteFieldFilter.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// A custom frontmatter field to match on: the key alone means "has it",
// key + value means "has it with exactly this value".
public struct NoteFieldFilter: Sendable {
    // MARK: - Property
    public let key: String
    public let value: String?

    // MARK: - Initializer
    public init(key: String, value: String?) {
        self.key = key
        self.value = value
    }

    // MARK: - Public
    // MARK: - Private
}
