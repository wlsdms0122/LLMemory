//
//  CorpusDBLintRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

protocol CorpusDBLintRule: LintRuleMeta {
    func check(_ scope: GRDBReadScope, _ tuning: LintTuning) throws -> [LintFinding]
}
