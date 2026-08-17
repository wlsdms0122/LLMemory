//
//  NoteDBLintRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

protocol NoteDBLintRule: LintRuleMeta {
    func check(_ db: Database, _ brain: BrainContext, note: NoteLintInput) throws -> [LintFinding]
}
