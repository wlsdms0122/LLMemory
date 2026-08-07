//
//  LintDocumentRule.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol LintDocumentRule: LintRuleMeta {
    func check(_ doc: LintEngine.Document) -> [LintEngine.Finding]
}
