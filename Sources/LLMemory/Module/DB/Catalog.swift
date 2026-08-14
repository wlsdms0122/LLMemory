//
//  Catalog.swift
//  LLMemory
//
//  Created by JSilver on 8/14/26.
//

import Foundation
import GRDB

// What the brain already knows about its corpus, handed to the one window that
// needs it before the index is rebuilt. A read-only facade so the tiers above
// can ask a question without the connection escaping the Module.
public struct Catalog {
    // MARK: - Property
    let reader: any DatabaseReader

    // MARK: - Initializer
    init(reader: any DatabaseReader) {
        self.reader = reader
    }

    // MARK: - Public
    public func seededNoteIds() throws -> [String] {
        try reader.read { database in try FetchSeededNoteIdsTransaction().perform(database) }
    }

    // MARK: - Private
}
