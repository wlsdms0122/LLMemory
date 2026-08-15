//
//  SingleTagRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Tags are the only classification a note has, so one tag means one way in.
// A note that is otherwise connected but carries a single label is reachable
// from one context only — that is under-classification, not minimalism.
struct SingleTagRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "tag-underclassified"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope) throws -> [LintFinding] {
        try scope.run(FetchFragmentationRowsTransaction())
            .filter { row in
                !(row.linkN == 0 && row.entN == 0 && row.tagN <= 1) && row.tagN <= 1
            }
            .map { row in
                .init("a single tag — one label is one way in", target: .note(row.nid))
            }
    }
    
    // MARK: - Private
}
