//
//  PurgeEnrichmentHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PurgeEnrichmentHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "recall path for a noisy model/batch: reject every retrieval term and delete every assoc edge carrying the given provenance. Goes through the same transaction gate as any op. Not a durable ban — a later re-proposal of a purged term re-opens it as pending (rows describe the latest proposal; validation re-judges it).",
        fields: [
            .required("provenance", "producer id to purge (matches note_retrieval_terms.provenance and note_links.provenance exactly)")
        ],
        example: ##"{"op":"purge_enrichment","provenance":"forge:capture:claude-sonnet-4-6"}"##
    )
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String? {
        nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let now = context.now
        let provenance = op["provenance"] as! String
        let (termsPurged, edgesPurged, affected) = try PurgeEnrichmentProvenanceOperation(
            provenance: provenance,
            now: now
        ).execute(db)
        
        return [
            "status": "ok",
            "ids": affected,
            "note": "purged \(termsPurged) term(s) + \(edgesPurged) edge(s) from provenance '\(provenance)'"
        ]
    }
    
    // MARK: - Private
}
