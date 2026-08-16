//
//  ReindexNoteFileTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReindexNoteFileTransaction: GRDBBrainTransaction {
    // MARK: - Property
    let path: URL

    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    init(path: URL) {
        self.path = path
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database, _ brain: BrainContext) throws -> String {
        if let rejection = brain.path.liveNoteRejection(of: path) {
            throw NotesError.notALiveNote(
                path: brain.path.relative(of: path) ?? path.path,
                reason: rejection
            )
        }

        let now = Int(Date().timeIntervalSince1970)

        var text = try String(contentsOf: path, encoding: .utf8)
        var (fields, body) = try frontmatter.parse(text)
        let tagsChanged = try normalizeTags(db, &fields)

        if tagsChanged {
            text = frontmatter.dump(fields) + body
            try text.write(to: path, atomically: true, encoding: .utf8)
        }

        return try UpsertNoteTransaction(file: path, fields: fields, body: body, raw: text, now: now)
            .perform(db, brain)
    }

    // MARK: - Private
    private func normalizeTags(
        _ db: Database,
        _ doc: inout FrontmatterDocument
    ) throws -> Bool {
        guard !doc.tags.isEmpty else { return false }

        var seen = Set<String>()
        var normalized: [String] = []

        for tag in doc.tags {
            let canonical = try CanonicalizeTagTransaction(tag: tag).perform(db)

            if seen.insert(canonical).inserted { normalized.append(canonical) }
        }

        if normalized == doc.tags { return false }

        doc.tags = normalized

        return true
    }
}
