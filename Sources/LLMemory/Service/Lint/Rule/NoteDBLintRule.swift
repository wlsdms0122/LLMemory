//
//  NoteDBLintRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

protocol NoteDBLintRule: LintRuleMeta {
    func check(_ scope: GRDBReadScope, _ brain: BrainContext, note: NoteLintInput) throws -> [LintFinding]
}
