//
//  DistinctCorpusRule.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// The well-behaved counterpart to CollidingCorpusRule — two findings with distinct identities, so the
// collision check has something that must pass as well as something that must fail.
struct DistinctCorpusRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-near-duplicate"
    let severity = LintEngine.Severity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ database: Database) throws -> [LintEngine.Finding] {
        [
            .init("one", target: .corpus("tag-pair:a|b"), key: "pair:a|b"),
            .init("two", target: .corpus("tag-pair:c|d"), key: "pair:c|d")
        ]
    }
    
    // MARK: - Private
}
