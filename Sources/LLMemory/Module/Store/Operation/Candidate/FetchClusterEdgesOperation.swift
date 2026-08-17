//
//  FetchClusterEdgesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Cluster substrate — surfaced, forget-exempt link and entity co-mention
// edges.
struct FetchClusterEdgesOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [(String, String)] {
        var edges: [(String, String)] = []

        for row in try Row.fetchAll(db, sql: """
            SELECT src, dst FROM note_links nl
            JOIN notes a ON a.id = nl.src
            JOIN notes b ON b.id = nl.dst
            WHERE \(Policy.all(Policy.surface("a"), Policy.forgetExempt("a")))
              AND \(Policy.all(Policy.surface("b"), Policy.forgetExempt("b")))
            """) {
            edges.append((row["src"], row["dst"]))
        }

        for row in try Row.fetchAll(db, sql: """
            SELECT e1.note_id AS a, e2.note_id AS b
            FROM entity_index e1 JOIN entity_index e2
              ON e1.entity = e2.entity AND e1.note_id < e2.note_id
            JOIN notes na ON na.id = e1.note_id
            JOIN notes nb ON nb.id = e2.note_id
            WHERE \(Policy.all(Policy.surface("na"), Policy.forgetExempt("na")))
              AND \(Policy.all(Policy.surface("nb"), Policy.forgetExempt("nb")))
            GROUP BY e1.note_id, e2.note_id
            """) {
            edges.append((row["a"], row["b"]))
        }

        return edges
    }

    // MARK: - Private
}
