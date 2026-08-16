//
//  ValidatePendingTermsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ValidatePendingTermsTransaction: GRDBBrainTransaction {
    private enum RejectReason: String {
        case roundtripFail = "roundtrip_fail"
        case idfCommon = "idf_common"
        case malformed = "malformed"
    }

    private enum IDFCheck {
        case common
        case allUnknown
        case ok
    }

    // MARK: - Property
    private static let idfMinCorpus = 8

    let noteIds: [String]?
    let keywords: any KeywordExtracting

    // MARK: - Initializer
    init(noteIds: [String]? = nil, keywords: any KeywordExtracting) {
        self.noteIds = noteIds
        self.keywords = keywords
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database, _ brain: BrainContext) throws -> TermValidationPass {
        var sql = """
            SELECT note_id, kind, term FROM note_retrieval_terms WHERE status = 'pending'
            """
        var arguments: [DatabaseValueConvertible] = []

        if let noteIds, !noteIds.isEmpty {
            let placeholders = Array(repeating: "?", count: noteIds.count).joined(separator: ",")
            sql += " AND note_id IN (\(placeholders))"
            arguments.append(contentsOf: noteIds)
        }

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        guard !rows.isEmpty else { return TermValidationPass() }

        let topK = brain.config.getInt("enrich.roundtrip_topk", default: 10)
        let dfCeiling = brain.config.getDouble("enrich.idf_df_ceiling", default: 0.25)
        let totalNotes = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM notes n WHERE \(Policy.surface())"
        ) ?? 0
        let now = Int(Date().timeIntervalSince1970)
        var result = TermValidationPass()
        var touchedNotes = Set<String>()

        for row in rows {
            let noteId: String = row["note_id"]
            let kind: String = row["kind"]
            let term: String = row["term"]
            let tokens = keywords.keywords(in: term, limit: 24)

            if tokens.isEmpty {
                try reject(db, nid: noteId, kind: kind, term: term, reason: .malformed, now: now)
                result.rejected += 1
                result.rejectBreakdown[RejectReason.malformed.rawValue, default: 0] += 1
                continue
            }

            if kind == "alias", totalNotes > 0 {
                switch try idfCheck(
                    db,
                    tokens: tokens,
                    totalNotes: totalNotes,
                    dfCeiling: dfCeiling
                ) {
                case .common:
                    try reject(
                        db,
                        nid: noteId,
                        kind: kind,
                        term: term,
                        reason: .idfCommon,
                        now: now
                    )
                    result.rejected += 1
                    result.rejectBreakdown[RejectReason.idfCommon.rawValue, default: 0] += 1
                    continue

                case .allUnknown:
                    result.stillPending += 1
                    continue

                case .ok:
                    break
                }
            }

            if try roundTrip(db, term: term, tokens: tokens, noteId: noteId, topK: topK) {
                try db.execute(sql: """
                    UPDATE note_retrieval_terms
                    SET status = 'active', validated_at = ?, reject_reason = NULL
                    WHERE note_id = ? AND kind = ? AND term = ?
                    """, arguments: [now, noteId, kind, term])
                result.activated += 1
                touchedNotes.insert(noteId)
            } else {
                result.stillPending += 1
            }
        }

        for noteId in touchedNotes {
            try SyncNoteEnrichTransaction(noteId: noteId).perform(db)
        }

        return result
    }

    // MARK: - Private
    private func reject(
        _ db: Database,
        nid: String,
        kind: String,
        term: String,
        reason: RejectReason,
        now: Int
    ) throws {
        try db.execute(sql: """
            UPDATE note_retrieval_terms
            SET status = 'rejected', reject_reason = ?, validated_at = ?
            WHERE note_id = ? AND kind = ? AND term = ?
            """, arguments: [reason.rawValue, now, nid, kind, term])
    }

    private func idfCheck(
        _ db: Database,
        tokens: [String],
        totalNotes: Int,
        dfCeiling: Double
    ) throws -> IDFCheck {
        let measureCommon = totalNotes >= Self.idfMinCorpus
        var anyKnown = false
        var allCommon = true

        for token in tokens {
            let documentFrequency = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT f.id) FROM notes_fts f JOIN notes n ON n.id = f.id "
                    + "WHERE notes_fts MATCH ? AND \(Policy.surface())",
                arguments: ["\"\(token.replacingOccurrences(of: "\"", with: ""))\""]
            ) ?? 0

            if documentFrequency > 0 {
                anyKnown = true

                if Double(documentFrequency) / Double(totalNotes) <= dfCeiling {
                    allCommon = false
                }
            } else {
                let inVocab = try Int.fetchOne(
                    db,
                    sql: "SELECT 1 FROM tag_vocab WHERE tag = ?",
                    arguments: [token]
                ) != nil
                let inEntity = try Int.fetchOne(
                    db,
                    sql: "SELECT 1 FROM entity_index WHERE entity = ? LIMIT 1",
                    arguments: [token]
                ) != nil

                if inVocab || inEntity {
                    anyKnown = true
                    allCommon = false
                }
            }
        }

        if !anyKnown { return .allUnknown }
        if measureCommon && allCommon { return .common }

        return .ok
    }

    private func roundTrip(
        _ db: Database,
        term: String,
        tokens: [String],
        noteId: String,
        topK: Int
    ) throws -> Bool {
        let parts = tokens.map { token in
            "\"\(token.replacingOccurrences(of: "\"", with: ""))\""
        }

        if parts.isEmpty { return false }

        let matchExpr = parts.joined(separator: " OR ")
        let currentEnrich = try String.fetchOne(
            db,
            sql: "SELECT enrich FROM notes_fts WHERE id = ? AND section = ''",
            arguments: [noteId]
        ) ?? ""
        let probe = currentEnrich.isEmpty ? term : currentEnrich + "\n" + term

        try db.execute(
            sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
            arguments: [probe, noteId]
        )

        defer {
            try? db.execute(
                sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
                arguments: [currentEnrich, noteId]
            )
        }

        let hits = try String.fetchAll(db, sql: """
            SELECT f.id FROM notes_fts f JOIN notes n ON n.id = f.id
            WHERE notes_fts MATCH ? AND \(Policy.surface())
            GROUP BY f.id
            ORDER BY MIN(rank), f.id LIMIT ?
            """, arguments: [matchExpr, topK])

        return hits.contains(noteId)
    }
}
