//
//  LintOutput.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A finding with its rule's identity attached — what the engine returns once
// it knows which rule spoke.
struct LintOutput {
    // MARK: - Property
    let severity: LintSeverity
    let code: String
    let message: String
    let target: LintTarget
    let key: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
