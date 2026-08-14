//
//  LintDocument.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A note's body as the document rules see it: lines, the headings over them,
// and which lines sit inside a code fence. Fenced lines are content to the
// author and noise to a pattern rule, so every rule reads them out.
struct LintDocument {
    // MARK: - Property
    let id: String
    let lines: [String]
    let sections: [LintSection]
    let inFence: [Bool]
    let unclosedFence: Int?

    // MARK: - Initializer
    // MARK: - Public
    func contentLineIndices() -> [Int] {
        lines.indices.filter { index in !inFence[index] }
    }

    // MARK: - Private
}
