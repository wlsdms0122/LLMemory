//
//  SearchRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One FTS hit — a struct rather than a tuple so surfaces can encode it
// without mirroring (extra carries the shared-term count on expanded rows).
public struct SearchRow: Sendable {
    // MARK: - Property
    public let path: String
    public let id: String
    public let title: String
    public let summary: String?
    public let tagsCSV: String?
    public let isStale: Bool
    public let section: String?
    public let extra: Int?
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
