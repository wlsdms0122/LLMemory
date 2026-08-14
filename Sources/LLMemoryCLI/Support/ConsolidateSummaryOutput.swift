//
//  ConsolidateSummaryOutput.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Every consolidate pass reports the same way — the result reflected, plain or
// JSON — so the passes do not each decide what reporting looks like.
struct ConsolidateSummaryOutput {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func emit<T: Encodable>(_ summary: T, json: Bool) {
        CommandOutput().renderReflected(summary, json: json)
    }

    // MARK: - Private
}
