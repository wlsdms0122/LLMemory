//
//  FetchNoteTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let nid: String

    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> (URL, FrontmatterDocument, String)? {
        guard try NoteExistsTransaction(nid: nid).perform(db) else { return nil }

        let path = brain.layout.file(forId: nid)
        let text = try String(contentsOf: path, encoding: .utf8)
        let (fields, body) = try frontmatter.parse(text)

        return (path, fields, body)
    }

    // MARK: - Private
}
