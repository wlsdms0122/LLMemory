//
//  NoteLintRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

protocol NoteLintRule: LintRuleMeta {
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding]
}
