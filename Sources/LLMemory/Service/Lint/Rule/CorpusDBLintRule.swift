//
//  CorpusDBLintRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

protocol CorpusDBLintRule: LintRuleMeta {
    func check(_ db: Database, _ tuning: LintTuning) throws -> [LintFinding]
}
