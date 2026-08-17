//
//  BudgetCut.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct BudgetCut: Sendable {
    // MARK: - Property
    public let shown: String
    public let shownSections: [TocEntry]
    public let omitted: [TocEntry]
    public let truncatedWithin: String?
    public let shownWords: Int
    public let totalWords: Int

    public var truncated: Bool { !omitted.isEmpty || truncatedWithin != nil }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
