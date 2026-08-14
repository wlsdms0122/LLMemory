//
//  SetGeneHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct SetGeneHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "set a gene's per-brain value directly. Works on every cataloged gene (locked "
        + "write-path genes included; the lock only bars the homeostasis loop). Bounds-checked; "
        + "recorded in genome_events with provenance. Pass value=null to reset to wild-type.",
        fields: [
            .required("gene", "gene id from `genome list`"),
            .optional("value", "new numeric value within the gene's bounds; null/absent resets to wild-type"),
            .optional("reason", "why — recorded as event detail")
        ],
        example: ##"{"op":"set_gene","gene":"links.sibling_rank_weight","value":0.2,"reason":"형제 도배 실측 완화"}"##
    )

    let genome: any GenomeServiceable

    private let payload = OpPayloadCheck()

    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let id = op["gene"] as? String ?? ""

        guard let definition = Genes.gene(id) else {
            return "unknown gene: '\(id)' — see `genome list` for the catalog"
        }

        if let raw = op["value"], !(raw is NSNull) {
            guard let value = payload.asDouble(raw) else { return "value must be numeric" }

            if value < definition.min || value > definition.max {
                return "value \(value) is outside gene '\(id)' bounds [\(definition.min), \(definition.max)]"
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
        let id = op["gene"] as! String
        let reason = op["reason"] as? String

        if let raw = op["value"], !(raw is NSNull), let value = payload.asDouble(raw) {
            let result = try genome.setGene(
                scope,
                id: id,
                value: value,
                cause: "set_gene",
                detail: reason,
                requireMutable: false,
                now: now
            )

            return [
                "status": "ok",
                "ids": [id],
                "note": "gene \(id): \(result.old) → \(result.new)"
            ]
        }

        let old = try genome.resetGene(scope, id: id, cause: "set_gene", now: now)

        return ["status": "ok", "ids": [id], "note": "gene \(id): \(old) → wild-type"]
    }

    // MARK: - Private
}
