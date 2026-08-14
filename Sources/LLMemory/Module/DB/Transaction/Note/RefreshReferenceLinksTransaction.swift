//
//  RefreshReferenceLinksTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RefreshReferenceLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let nid: String
    let body: String
    let now: Int

    // MARK: - Initializer
    init(nid: String, body: String, now: Int) {
        self.nid = nid
        self.body = body
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var candidates = Set<String>()

        for regex in [Notes.backtickIdRegex, Notes.wikilinkRegex] {
            regex.enumerateMatches(in: body, range: range) { match, _, _ in
                guard let match else { return }

                candidates.insert(nsBody.substring(with: match.range(at: 1)))
            }
        }

        candidates.remove(nid)

        try db.execute(sql: "DELETE FROM note_ref_markers WHERE src = ?", arguments: [nid])

        for marker in candidates.sorted() {
            try db.execute(sql: """
                INSERT INTO note_ref_markers (src, marker, created_at) VALUES (?, ?, ?)
                """, arguments: [nid, marker, now])
        }

        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? AND kind = ?",
            arguments: [nid, Links.kindReference]
        )
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
            SELECT m.src, n.id, ?, 1.0, ?, ?
            FROM note_ref_markers m JOIN notes n ON n.id = m.marker
            WHERE m.src = ?
            """, arguments: [Links.kindReference, now, now, nid])
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
            SELECT m.src, ?, ?, 1.0, ?, ?
            FROM note_ref_markers m JOIN notes s ON s.id = m.src
            WHERE m.marker = ? AND m.src != ?
            """, arguments: [nid, Links.kindReference, now, now, nid, nid])
    }

    // MARK: - Private
}
