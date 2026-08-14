//
//  LintRuleMeta.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation

protocol LintRuleMeta: Sendable {
    var code: String { get }
    var severity: LintSeverity { get }
}
