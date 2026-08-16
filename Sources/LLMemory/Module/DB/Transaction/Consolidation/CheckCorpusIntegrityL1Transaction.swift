//
//  CheckCorpusIntegrityL1Transaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CheckCorpusIntegrityL1Transaction: GRDBBrainReadTransaction {
    private let noteFiles = Notes()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> (checked: Int, issues: [String]) {
        let ids = try String.fetchAll(db, sql: "SELECT id FROM notes ORDER BY id")
        let issues = try ids.compactMap { id -> String? in
            let path = brain.paths.file(forId: id)
            let relative = brain.paths.relative(of: path) ?? path.path
            
            do {
                guard try noteFiles.readNoteIfPresent(at: path) != nil else {
                    return "missing: \(id) → \(relative)"
                }
                
                return nil
            } catch let error as NoteUnreadable {
                return "unreadable: \(id) → \(relative): \(error.reason)"
            }
        }
        
        return (ids.count, issues)
    }

    // MARK: - Private
}
