//
//  TermValidationPass.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// note_retrieval_terms validation transactions — the round-trip and IDF
// gates that keep weak-model enrichment from polluting the index.
public struct TermValidationPass: Sendable {
    // MARK: - Property
    public var activated: Int = 0
    public var rejected: Int = 0
    public var stillPending: Int = 0
    public var rejectBreakdown: [String: Int] = [:]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
