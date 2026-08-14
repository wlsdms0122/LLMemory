//
//  FetchNoteTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (URL, FrontmatterDoc, String)? {
        guard try NoteExistsTransaction(nid: nid).perform(db) else { return nil }

        let path = Paths.file(forId: nid)
        let text = try String(contentsOf: path, encoding: .utf8)
        let (fields, body) = try Frontmatter.parse(text)

        return (path, fields, body)
    }

    // MARK: - Private
}
