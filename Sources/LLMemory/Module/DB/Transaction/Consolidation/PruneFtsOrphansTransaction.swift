//
//  PruneFtsOrphansTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PruneFtsOrphansTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> (orphansPruned: Int, refilled: Int, unreadable: [String]) {
        let noteIds = Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
        let ftsIds = Set(try String.fetchAll(db, sql: "SELECT DISTINCT id FROM notes_fts"))
        let orphans = ftsIds.subtracting(noteIds)
        
        for orphanId in orphans {
            try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [orphanId])
        }
        
        let missing = noteIds.subtracting(ftsIds)
        var refilled = 0
        var unreadable: [String] = []
        
        for noteId in missing {
            let row = try Row.fetchOne(
                db,
                sql: "SELECT title, summary FROM notes WHERE id = ?",
                arguments: [noteId]
            )
            
            guard let row else { continue }
            
            let title: String = row["title"]
            let summary: String? = row["summary"]
            let path = Paths.file(forId: noteId)
            let body: String
            do {
                guard let read = try Notes.readNoteIfPresent(at: path) else { continue }
                
                body = read.body
            } catch let error as NoteUnreadable {
                unreadable.append("\(noteId): \(error)")
                continue
            }
            
            try ReindexNoteFTSTransaction(noteId: noteId,
                title: title,
                summary: summary ?? "",
                body: body
            ).perform(db)
            refilled += 1
        }
        
        return (orphans.count, refilled, unreadable.sorted())
    }

    // MARK: - Private
}
