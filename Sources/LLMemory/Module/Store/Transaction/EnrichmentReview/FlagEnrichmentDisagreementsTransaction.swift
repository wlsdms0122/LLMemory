//
//  FlagEnrichmentDisagreementsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FlagEnrichmentDisagreementsTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int
    let disagreeFloor: Double

    private let vectorMath = VectorMath()

    // MARK: - Initializer
    init(now: Int, disagreeFloor: Double) {
        self.now = now
        self.disagreeFloor = disagreeFloor
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> EnrichmentReviewPass {
        var pass = EnrichmentReviewPass()
        let vectors = try FetchNoteVectorsTransaction().perform(db)

        guard !vectors.isEmpty else { return pass }

        let floor = disagreeFloor
        let edges = try Row.fetchAll(db, sql: """
            SELECT src, dst, provenance FROM note_links WHERE kind = ?
            """, arguments: [LinkKind.assoc.rawValue])
        var flagged = Set<String>()

        for edge in edges {
            let src: String = edge["src"]
            let dst: String = edge["dst"]

            guard let srcVector = vectors[src], let dstVector = vectors[dst] else { continue }

            let similarity = vectorMath.cosine(srcVector, dstVector)

            if similarity < floor {
                for noteId in [src, dst] {
                    try AddRippleFlagTransaction(
                        noteId: noteId,
                        kind: EnrichmentReview.flagKind,
                        reason: "assoc edge \(src)↔\(dst) cosine \(String(format: "%.3f", similarity)) < floor \(String(format: "%.2f", floor))",
                        now: now
                    ).perform(db)
                    flagged.insert(noteId)
                }
            }
        }

        pass.flagged = flagged.count

        let open = try String.fetchAll(db, sql: """
            SELECT note_id FROM ripple_flags WHERE flag = ? AND resolved_at IS NULL
            """, arguments: [EnrichmentReview.flagKind])

        for noteId in open where !flagged.contains(noteId) {
            pass.resolved += try ResolveRippleFlagTransaction(
                noteId: noteId,
                kind: EnrichmentReview.flagKind,
                reason: "disagreement cleared (cosine recovered or edge pruned)",
                now: now
            ).perform(db)
        }

        return pass
    }

    // MARK: - Private
}
