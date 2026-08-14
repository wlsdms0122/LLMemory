//
//  NoteStats.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Observation transactions — per-note, per-prefix, and corpus-wide stats.
public struct NoteStats: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let priority: String
    public let createdAt: Int
    public let editedAt: Int
    public let ageDays: Int?
    public let sinceEditDays: Int?
    public let sinceRetrievalDays: Int?
    public let hitCount: Int
    public let wordCount: Int
    public let sectionCount: Int
    public let stale: Bool
    public let tagCount: Int
    public let linkCount: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
