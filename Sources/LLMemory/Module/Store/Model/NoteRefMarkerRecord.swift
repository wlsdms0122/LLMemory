//
//  NoteRefMarkerRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteRefMarkerRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case src
        case marker
        case createdAt
    }

    // MARK: - Property
    let src: String
    let marker: String
    let createdAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteRefMarkerRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_ref_markers" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
