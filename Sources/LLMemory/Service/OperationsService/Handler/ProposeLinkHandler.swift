//
//  ProposeLinkHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct ProposeLinkHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "propose an LLM semantic-association edge (kind=assoc) between two notes at a low dormant weight. No separate validation: the edge starts BELOW the traversal floor (links.neighbor_floor 0.5) so retrieval ignores it until co-retrieval strengthens it past 0.5; if never used, decay prunes it. The existing Hebbian decay/strengthen loop IS the validator (synaptic pruning).",
        fields: [
            .required("src", role: .noteId, "source note id"),
            .required("dst", role: .noteId, "destination note id (must differ from src)"),
            .optional("kind", "link kind — only 'assoc' is accepted; default 'assoc'"),
            .optional("provenance", "producer id; used for batch audit + purge_enrichment recall"),
            .optional("confidence", "(0,1] LLM self-reported confidence; uncalibrated, so it only positions the initial weight within the dormant band [links.proposed_initial_weight, links.neighbor_floor) — higher = closer to the traversal floor, never at or above it. Default 1.0.")
        ],
        example: ##"{"op":"propose_link","src":"note-a","dst":"note-b","kind":"assoc","confidence":0.8,"provenance":"forge:capture:claude-sonnet-4-6"}"##
    )
    
    private let noteExistence = NoteExistence()
    private let number = PayloadNumber()
    
    private let links = Links()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let src = op["src"] as? String ?? ""
        let dst = op["dst"] as? String ?? ""
        
        if src == dst { return "src and dst must differ" }
        
        if let rawKind = op["kind"] {
            let kind = rawKind as? String ?? ""
            
            if kind != Links.kindAssoc {
                return "invalid kind: \(kind) (propose_link only supports 'assoc')"
            }
        }
        
        if let rejection = try noteExistence.rejectionForUnknown(src, context: context, scope: scope) {
            return "src: \(rejection)"
        }
        
        if let rejection = try noteExistence.rejectionForUnknown(dst, context: context, scope: scope) {
            return "dst: \(rejection)"
        }
        
        if op["confidence"] != nil {
            guard let confidence = number.value(of: op["confidence"]),
                confidence > 0, confidence <= 1
            else {
                return "confidence must be a number in (0, 1]"
            }
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
        let src = op["src"] as! String
        let dst = op["dst"] as! String
        let kind = (op["kind"] as? String)
            .flatMap { value in value.isEmpty ? nil : value } ?? Links.kindAssoc
        let provenance = (op["provenance"] as? String)
            .flatMap { value in value.isEmpty ? nil : value }
        let confidence = number.value(of: op["confidence"]) ?? 1.0
        let base = Genes.double("links.proposed_initial_weight")
        let neighborFloor = Genes.double("links.neighbor_floor")
        let ceiling = neighborFloor - 0.02
        let weight = min(ceiling, base + max(0, ceiling - base) * confidence)
        
        guard let (source, destination) = links.normalize(src: src, dst: dst, kind: kind) else {
            return ["status": "ok", "ids": [], "note": "skipped self-loop \(src)"]
        }
        
        try scope.run(UpsertAssocLinkTransaction(
            src: source,
            dst: destination,
            kind: kind,
            weight: weight,
            now: now,
            provenance: provenance
        ))
        
        return [
            "status": "ok",
            "ids": [source, destination],
            "note": "proposed \(kind) edge \(source)→\(destination) (weight \(String(format: "%.2f", weight)), dormant)"
        ]
    }
    
    // MARK: - Private
}
