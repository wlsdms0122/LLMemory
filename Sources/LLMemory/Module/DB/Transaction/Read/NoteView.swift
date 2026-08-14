//
//  NoteView.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct NoteView: Sendable {
    // MARK: - Property
    public let id, path: String
    public let frontmatter: NoteFrontmatter
    public let body: String
    public let hitCount, createdAt, editedAt: Int
    public let priority: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
