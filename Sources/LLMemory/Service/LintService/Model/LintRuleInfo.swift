//
//  LintRuleInfo.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A rule as the catalog surface describes it — what it is called, how loudly
// it speaks, and what it needs to see in order to speak at all.
public struct LintRuleInfo: Encodable {
    // MARK: - Property
    public let code: String
    public let severity: String
    public let scope: String
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
