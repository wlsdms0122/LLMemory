//
//  FetchNoteVectorsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteVectorsOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String: [Float]] {
        var vectors: [String: [Float]] = [:]
        let rows = try Row.fetchAll(db, sql: "SELECT note_id, dim, vec FROM note_vectors")

        for row in rows {
            let noteId: String = row["note_id"]
            let dim: Int = row["dim"]

            guard let data: Data = row["vec"],
                data.count == dim * MemoryLayout<Float>.size
            else {
                continue
            }

            vectors[noteId] = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }

        return vectors
    }

    // MARK: - Private
}
