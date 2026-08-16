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
    // The thresholds a note rule judges size and growth by, resolved when
    // the corpus was read. Values, not the Config that answers them: a live
    // reference would let a write scope swap the cache mid-pass and score the
    // last note of a run against a different bar than the first.
    let oversizedWords: Int
    let growthMinDatedSections: Int
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
