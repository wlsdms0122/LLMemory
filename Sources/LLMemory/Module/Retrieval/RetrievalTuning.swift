//
//  RetrievalTuning.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// How far and how hard retrieval reaches, resolved from one brain's genes.
//
// Every gene the read path is tuned by is named here once. The transactions
// take the numbers — how wide to expand is a judgement about association, not
// something a row reader decides — and the genome shadow replay builds this
// from a brain with one gene swapped, so a replay says which values it ran
// with instead of the query re-deriving them mid-flight.
struct RetrievalTuning: Sendable {
    // MARK: - Property
    // How many FTS hits seed an associative snapshot.
    let similarLimit: Int

    // How many link hops the snapshot expands through.
    let expandHops: Int

    // Weight below which a link is not worth following.
    let neighborFloor: Double

    // How much a sibling link is discounted against a deliberate one.
    let siblingDiscount: Double

    // Minutes of session history that prime the tag rerank.
    let primingWindowMin: Int

    // How strongly the primed tags pull a hit up the ranking.
    let primingAlpha: Double

    // MARK: - Initializer
    init(
        similarLimit: Int,
        expandHops: Int,
        neighborFloor: Double,
        siblingDiscount: Double,
        primingWindowMin: Int,
        primingAlpha: Double
    ) {
        self.similarLimit = similarLimit
        self.expandHops = expandHops
        self.neighborFloor = neighborFloor
        self.siblingDiscount = siblingDiscount
        self.primingWindowMin = primingWindowMin
        self.primingAlpha = primingAlpha
    }

    // MARK: - Public
    // MARK: - Private
}
