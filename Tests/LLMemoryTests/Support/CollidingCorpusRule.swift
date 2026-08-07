//
//  CollidingCorpusRule.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// A deliberately broken corpus rule: two findings that claim the same identity. Used to check that
// the lint surface reports the collision instead of quietly keeping one of them.
struct CollidingCorpusRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-near-duplicate"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ database: Database) throws -> [LintEngine.Finding] {
        [
            .init("one", target: .corpus("tag-pair:a|b"), key: "pair:a|b"),
            .init("two", target: .corpus("tag-pair:a|b"), key: "pair:a|b")
        ]
    }
    
    // MARK: - Private
}
