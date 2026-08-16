//
//  LintCorpusIndex.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct LintCorpusIndex {
    // MARK: - Property
    let ids: Set<String>
    let tagAliases: [String: String]
    // The thresholds a note rule judges size and growth by. They belong to
    // this brain rather than to the binary, so they arrive with the corpus
    // the rule is judging against.
    let config: Config
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
