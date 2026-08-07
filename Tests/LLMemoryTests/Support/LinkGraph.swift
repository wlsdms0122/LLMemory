//
//  LinkGraph.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Reads the tables that record how notes point at each other — derived edges, the markers they come
// from, and the flags raised when the two stop agreeing.
struct LinkGraph {
    // MARK: - Property
    private let home: any BrainHome
    
    // MARK: - Initializer
    init(_ home: any BrainHome) {
        self.home = home
    }
    
    // MARK: - Public
    func referenceEdges(from source: String, to destination: String) throws -> Int {
        try count(sql: """
            SELECT COUNT(*) FROM note_links WHERE src = ? AND dst = ? AND kind = 'reference'
            """, arguments: [source, destination])
    }
    
    func edges(pointingAt destination: String) throws -> Int {
        try count(sql: "SELECT COUNT(*) FROM note_links WHERE dst = ?", arguments: [destination])
    }
    
    func markers(from source: String, to marker: String) throws -> Int {
        try count(
            sql: "SELECT COUNT(*) FROM note_ref_markers WHERE src = ? AND marker = ?",
            arguments: [source, marker]
        )
    }
    
    func unresolvedStaleReferenceFlags(on noteId: String) throws -> Int {
        try count(sql: """
            SELECT COUNT(*) FROM ripple_flags
            WHERE note_id = ? AND flag = 'stale_ref' AND resolved_at IS NULL
            """, arguments: [noteId])
    }
    
    // MARK: - Private
    private func count(sql: String, arguments: StatementArguments) throws -> Int {
        try home.read { database in try Int.fetchOne(database, sql: sql, arguments: arguments) ?? 0 }
    }
}
