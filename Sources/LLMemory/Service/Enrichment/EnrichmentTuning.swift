//
//  EnrichmentTuning.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// What the enrichment passes are tuned by, resolved from one brain's config.
//
// The keys and their defaults live here and nowhere else. The transactions
// that act on these numbers take them as parameters — a store transaction
// that read `enrich.disagree_floor` for itself would be the database layer
// deciding what counts as disagreement — so without one owner the same
// default would be spelled at each of the three call sites that pass them
// down, and drift the first time one is tuned.
struct EnrichmentTuning: Sendable {
    // MARK: - Property
    // Cosine below which an LLM-proposed edge disagrees with the corpus.
    let disagreeFloor: Double

    // How deep the round-trip search looks for the note a term claims.
    let roundtripTopK: Int

    // Document frequency above which a term is too common to be a cue.
    let idfDFCeiling: Double

    // Provenance disagreement rate at which a model is reported as noisy.
    let modelAlarmRate: Double

    // MARK: - Initializer
    init(_ config: Config) {
        disagreeFloor = config.getDouble("enrich.disagree_floor", default: 0.15)
        roundtripTopK = config.getInt("enrich.roundtrip_topk", default: 10)
        idfDFCeiling = config.getDouble("enrich.idf_df_ceiling", default: 0.25)
        modelAlarmRate = config.getDouble("enrich.model_alarm_rate", default: 0.4)
    }

    // MARK: - Public
    // MARK: - Private
}
