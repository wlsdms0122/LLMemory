//
//  ReindexNoteFileOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReindexNoteFileOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, URL)
    // The address the file was resolved to — the caller has already refused
    // anything that is not a live note of this brain.
    let noteId: String
    let path: URL

    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    init(noteId: String, path: URL) {
        self.noteId = noteId
        self.path = path
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> String {
        let now = Int(Date().timeIntervalSince1970)

        var text = try String(contentsOf: path, encoding: .utf8)
        var (fields, body) = try frontmatter.parse(text)
        let tagsChanged = try normalizeTags(db, &fields)

        if tagsChanged {
            text = frontmatter.dump(fields) + body
            try text.write(to: path, atomically: true, encoding: .utf8)
        }

        return try UpsertNoteOperation(
            noteId: noteId,
            file: path,
            fields: fields,
            body: body,
            raw: text,
            now: now
        )
            .execute(db)
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
            let canonical = try CanonicalizeTagOperation(tag: tag).execute(db)

            if seen.insert(canonical).inserted { normalized.append(canonical) }
        }

        if normalized == doc.tags { return false }

        doc.tags = normalized

        return true
    }
}
