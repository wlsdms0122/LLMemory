//
//  LintFinding.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// What a rule says it found. The target is optional because most rules speak
// about the note they were handed; only a rule that speaks about the corpus
// has to name its own subject.
struct LintFinding {
    // MARK: - Property
    let message: String
    let target: LintTarget?
    let key: String?

    // MARK: - Initializer
    init(_ message: String, target: LintTarget? = nil, key: String? = nil) {
        self.message = message
        self.target = target
        self.key = key
    }

    // MARK: - Public
    // MARK: - Private
}
