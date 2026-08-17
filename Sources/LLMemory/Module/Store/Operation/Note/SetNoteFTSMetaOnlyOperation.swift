//
//  SetNoteFTSMetaOnlyOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SetNoteFTSMetaOnlyOperation: GRDBOperation {
    // MARK: - Property
    let nid: String
    let title: String
    let summary: String?

    // MARK: - Initializer
    init(nid: String, title: String, summary: String?) {
        self.nid = nid
        self.title = title
        self.summary = summary
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try ReindexNoteFTSOperation(noteId: nid, title: title, summary: summary ?? "", body: "")
            .execute(db)
    }

    // MARK: - Private
}
