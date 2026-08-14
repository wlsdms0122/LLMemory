//
//  LintSection.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// One heading and the span it owns, with the full heading path that addresses
// it — the same path `query get --section` takes.
struct LintSection {
    // MARK: - Property
    let level: Int
    let title: String
    let lineStart: Int
    let lineEnd: Int
    let path: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
