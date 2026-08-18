//
//  FetchNoteCascadeTablesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteCascadeTablesOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        let tables = try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
        var cascading: [String] = []
        
        for table in tables {
            let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))")
            let cascades = foreignKeys.contains { row in
                (row["table"] as String?) == "notes"
                    && ((row["on_delete"] as String?)?.uppercased().contains("CASCADE") ?? false)
            }
            
            if cascades { cascading.append(table) }
        }
        
        return cascading
    }

    // MARK: - Private
}
