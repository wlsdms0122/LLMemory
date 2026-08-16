//
//  ActivationTuning.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// What the activity derivation is tuned by, resolved from one brain.
//
// The keys and their defaults live here and nowhere else. The transactions
// that group events into windows take these as numbers — how long a gap ends
// a session is a judgement about attention, not something a row writer knows.
struct ActivationTuning: Sendable {
    // MARK: - Property
    // Silence long enough to end one activity window and open the next.
    let windowGapSec: Int

    // How far back a retrieval hit may be and still be claimable as used.
    let usedLookbackSec: Int

    // MARK: - Initializer
    init(_ brain: BrainContext) {
        windowGapSec = brain.genes.int("activation.window_gap_sec")
        usedLookbackSec = brain.config.getInt("activation.used_lookback_sec", default: 86_400)
    }

    // MARK: - Public
    // MARK: - Private
}
