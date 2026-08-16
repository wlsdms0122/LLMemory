//
//  LintTuning.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// The thresholds the note rules judge by, resolved from one brain's config.
//
// The keys and their defaults live here and nowhere else. What counts as an
// oversized note is a lint judgement, so the store transaction that reads the
// corpus takes these as numbers rather than answering them for itself.
struct LintTuning: Sendable {
    // MARK: - Property
    // Word count above which a note is reported as oversized.
    let oversizedWords: Int

    // How many dated sections a note needs before unbounded growth is claimed.
    let growthMinDatedSections: Int

    // How many notes share a stem before they are treated as a family.
    let fragmentMinFamily: Int

    // MARK: - Initializer
    init(_ config: Config) {
        oversizedWords = config.getInt("lint.oversized_words", default: 2_000)
        growthMinDatedSections = config.getInt("lint.growth_min_dated_sections", default: 8)
        fragmentMinFamily = config.getInt("lint.fragment_min_family", default: 3)
    }

    // MARK: - Public
    // MARK: - Private
}
