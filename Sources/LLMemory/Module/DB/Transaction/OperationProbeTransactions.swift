//
//  OperationProbeTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Probes and small writes the operation handlers compose — each one row
// vocabulary the mutation engine validates and applies through.
struct FetchNotePriorityTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT priority FROM notes WHERE id = ?",
            arguments: [nid]
        )
    }

    // MARK: - Private
}

struct FetchNoteStaleStateTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    // nil when the note is unknown.
    func perform(_ db: Database) throws -> Bool? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT stale FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }

        return (row["stale"] as Int? ?? 0) != 0
    }

    // MARK: - Private
}

struct NoteSourceTrackedTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM note_source WHERE note_id = ?",
            arguments: [nid]
        ) != nil
    }

    // MARK: - Private
}

// Read-only union check for mark_used validation — a note counts as
// surfaced when it appears in a derived hit *or* in a retrieval event not
// yet succeeded into hits, so validation never needs to write. Set-valued:
// the batch is judged with one hits query and one event scan.
struct NotesSurfacedRecentlyTransaction: GRDBReadTransaction {
    // MARK: - Property
    // Keeps each IN (...) under SQLite's bind-variable ceiling — batch size
    // must not decide the judgement's error path.
    private static let chunkSize = 500

    let noteIds: [String]
    let cutoff: Int
    let label: String?

    // MARK: - Initializer
    init(noteIds: [String], cutoff: Int, label: String? = nil) {
        self.noteIds = noteIds
        self.cutoff = cutoff
        self.label = label
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        guard !noteIds.isEmpty else { return [] }

        var surfaced = Set<String>()
        let wanted = Set(noteIds)
        let chunks = stride(from: 0, to: noteIds.count, by: Self.chunkSize).map { start in
            Array(noteIds[start..<min(start + Self.chunkSize, noteIds.count)])
        }

        for chunk in chunks {
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")

            if let label, !label.isEmpty {
                surfaced.formUnion(try String.fetchAll(db, sql: """
                    SELECT DISTINCT h.note_id FROM retrieval_hits h
                    JOIN activity_windows w ON w.id = h.window_id
                    WHERE h.note_id IN (\(placeholders)) AND h.surfaced_at >= ? AND w.label = ?
                    """, arguments: StatementArguments(chunk + [cutoff, label] as [DatabaseValueConvertible])))
            } else {
                surfaced.formUnion(try String.fetchAll(db, sql: """
                    SELECT DISTINCT note_id FROM retrieval_hits
                    WHERE note_id IN (\(placeholders)) AND surfaced_at >= ?
                    """, arguments: StatementArguments(chunk + [cutoff] as [DatabaseValueConvertible])))
            }
        }

        if surfaced.isSuperset(of: wanted) { return surfaced }

        let rows: [Row]

        if let label, !label.isEmpty {
            rows = try Row.fetchAll(db, sql: """
                SELECT payload FROM events
                WHERE kind = 'retrieval' AND ts >= ? AND session_id = ?
                """, arguments: [cutoff, label])
        } else {
            rows = try Row.fetchAll(db, sql: """
                SELECT payload FROM events WHERE kind = 'retrieval' AND ts >= ?
                """, arguments: [cutoff])
        }

        for row in rows {
            guard let raw = row["payload"] as String?,
                let data = raw.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let ids = (payload["hit_ids"] as? [String] ?? [])
                + (payload["expand_ids"] as? [String] ?? [])

            surfaced.formUnion(wanted.intersection(ids))

            if surfaced.isSuperset(of: wanted) { break }
        }

        return surfaced
    }

    // MARK: - Private
}

struct UpsertPendingTermTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let kind: String
    let term: String
    let provenance: String?
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, term: String, provenance: String?, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.term = term
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    // Inserts pending or revives a rejected row; returns the change count so
    // the handler can report how many landed.
    @discardableResult
    func perform(_ db: Database) throws -> Int {
        try db.execute(sql: """
            INSERT INTO note_retrieval_terms
              (note_id, kind, term, status, provenance, created_at)
            VALUES (?, ?, ?, 'pending', ?, ?)
            ON CONFLICT(note_id, kind, term) DO UPDATE SET
              status = 'pending',
              provenance = excluded.provenance,
              reject_reason = NULL,
              validated_at = NULL,
              created_at = excluded.created_at
            WHERE note_retrieval_terms.status = 'rejected'
            """, arguments: [noteId, kind, term, provenance, now])

        return db.changesCount
    }

    // MARK: - Private
}

struct InsertPendingTermIfAbsentTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let kind: String
    let term: String
    let provenance: String?
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, term: String, provenance: String?, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.term = term
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_retrieval_terms
              (note_id, kind, term, status, provenance, created_at)
            VALUES (?, ?, ?, 'pending', ?, ?)
            """, arguments: [noteId, kind, term, provenance, now])
    }

    // MARK: - Private
}

struct UpsertAssocLinkTransaction: GRDBTransaction {
    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let weight: Double
    let now: Int
    let provenance: String?

    // MARK: - Initializer
    init(src: String, dst: String, kind: String, weight: Double, now: Int, provenance: String?) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.weight = weight
        self.now = now
        self.provenance = provenance
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(src, dst, kind) DO UPDATE SET
              last_activated_at = excluded.last_activated_at
            """, arguments: [src, dst, kind, weight, now, now, provenance])
    }

    // MARK: - Private
}

struct PurgeEnrichmentProvenanceTransaction: GRDBTransaction {
    // MARK: - Property
    let provenance: String
    let now: Int

    // MARK: - Initializer
    init(provenance: String, now: Int) {
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (termsPurged: Int, edgesPurged: Int, affected: [String]) {
        let affected = try String.fetchAll(db, sql: """
            SELECT DISTINCT note_id FROM note_retrieval_terms
            WHERE provenance = ? AND status != 'rejected'
            """, arguments: [provenance])

        try db.execute(sql: """
            UPDATE note_retrieval_terms
            SET status = 'rejected', reject_reason = 'purged', validated_at = ?
            WHERE provenance = ? AND status != 'rejected'
            """, arguments: [now, provenance])

        let termsPurged = db.changesCount

        try db.execute(sql: "DELETE FROM note_links WHERE provenance = ?", arguments: [provenance])

        let edgesPurged = db.changesCount

        for noteId in affected {
            try SyncNoteEnrichTransaction(noteId: noteId).perform(db)
        }

        return (termsPurged, edgesPurged, affected)
    }

    // MARK: - Private
}

struct TouchNoteUsageTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let now: Int

    // MARK: - Initializer
    init(noteId: String, now: Int) {
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
            VALUES (?, 0, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET last_retrieved_at = excluded.last_retrieved_at
            """, arguments: [noteId, now, now])
    }

    // MARK: - Private
}

struct FetchNoteEntityHitsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(entity: String, hits: Int)] {
        try Row.fetchAll(
            db,
            sql: "SELECT entity, hit_count FROM entity_index WHERE note_id = ?",
            arguments: [noteId]
        )
            .map { row in (entity: row["entity"], hits: row["hit_count"]) }
    }

    // MARK: - Private
}

struct SetEntityHitCountTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let entity: String
    let hits: Int

    // MARK: - Initializer
    init(noteId: String, entity: String, hits: Int) {
        self.noteId = noteId
        self.entity = entity
        self.hits = hits
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE entity_index SET hit_count = ? WHERE note_id = ? AND entity = ?",
            arguments: [hits, noteId, entity]
        )
    }

    // MARK: - Private
}

struct FetchActiveTermRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(kind: String, term: String, provenance: String?)] {
        try Row.fetchAll(db, sql: """
            SELECT kind, term, provenance FROM note_retrieval_terms WHERE note_id = ? AND status = 'active'
            """, arguments: [noteId])
            .map { row in (kind: row["kind"], term: row["term"], provenance: row["provenance"]) }
    }

    // MARK: - Private
}

struct NoteLockedTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT locked FROM notes WHERE id = ?",
            arguments: [nid]
        ) == 1
    }

    // MARK: - Private
}

struct FetchTemplateDependentNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let templateIds: [String]

    // MARK: - Initializer
    init(templateIds: [String]) {
        self.templateIds = templateIds
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        guard !templateIds.isEmpty else { return [] }

        let placeholders = templateIds.map { _ in "?" }.joined(separator: ",")

        return try String.fetchAll(
            db,
            sql: "SELECT id FROM notes WHERE template IN (\(placeholders))",
            arguments: StatementArguments(templateIds)
        )
    }

    // MARK: - Private
}

struct SeedInitialLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let tags: [String]

    // MARK: - Initializer
    init(nid: String, tags: [String]) {
        self.nid = nid
        self.tags = tags
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        if tags.isEmpty { return }

        let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible] = []
        arguments.append(contentsOf: tags)
        arguments.append(nid)

        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, COUNT(*) AS shared,
                   (SELECT COUNT(*) FROM tags WHERE note_id = n.id) AS other_total
            FROM tags t JOIN notes n ON n.id = t.note_id
            WHERE t.tag IN (\(placeholders)) AND n.id != ?
            GROUP BY n.id
            ORDER BY shared DESC, n.id ASC
            LIMIT 5
            """, arguments: StatementArguments(arguments))

        if rows.isEmpty { return }

        let now = Int(Date().timeIntervalSince1970)
        let kind = Links.kindCooccur
        let newTotal = tags.count

        for row in rows {
            let candidateId: String = row["id"]
            let shared: Int = row["shared"]
            let otherTotal: Int = row["other_total"] as Int? ?? 0

            guard let (source, destination) = Links.normalize(
                src: nid,
                dst: candidateId,
                kind: kind
            ) else {
                continue
            }

            let union = max(newTotal + otherTotal - shared, 1)
            let weight = max(Double(shared) / Double(union), 0.1)

            try db.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(src, dst, kind) DO UPDATE SET
                  weight = MIN(1.0, weight + excluded.weight),
                  last_activated_at = excluded.last_activated_at
                """, arguments: [source, destination, kind, weight, now, now])
        }
    }

    // MARK: - Private
}
