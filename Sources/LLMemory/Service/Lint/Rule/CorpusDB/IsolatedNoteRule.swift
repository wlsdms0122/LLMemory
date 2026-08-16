//
//  IsolatedNoteRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct IsolatedNoteRule: CorpusDBLintRule {
    // MARK: - Property
    let code = "isolated"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ scope: GRDBReadScope, _ tuning: LintTuning) throws -> [LintFinding] {
        try scope.run(FetchFragmentationRowsTransaction())
            .filter { row in row.linkN == 0 && row.entN == 0 && row.tagN <= 1 }
            .map { row in
                .init("no links, no entities, ≤1 tag — orphan", target: .note(row.nid))
            }
    }
    
    // MARK: - Private
}
