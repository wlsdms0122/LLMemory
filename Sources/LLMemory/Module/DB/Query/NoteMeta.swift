//
//  NoteMeta.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum NoteMeta {
    static func get(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String
    ) throws -> String? {
        try NoteMetaRecord.fetchOne(db, key: [
            "note_id": noteId,
            "namespace": namespace,
            "key": key
        ])?
            .value
    }

    static func getAll(
        _ db: Database,
        noteId: String,
        namespace: String? = nil
    ) throws -> [String: [String: String]] {
        var request = NoteMetaRecord.filter(Column("note_id") == noteId)

        if let namespace {
            request = request.filter(Column("namespace") == namespace)
        }

        var values: [String: [String: String]] = namespace.map { namespace in [namespace: [:]] } ?? [:]

        for record in try request.fetchAll(db) {
            values[record.namespace, default: [:]][record.key] = record.value
        }

        return values
    }

    static func setValue(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String,
        value: String,
        now: Int
    ) throws {
        try NoteMetaRecord(
            noteId: noteId,
            namespace: namespace,
            key: key,
            value: value,
            updatedAt: now
        )
            .upsert(db)
    }

    @discardableResult
    static func delete(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String
    ) throws -> Int {
        try NoteMetaRecord.deleteOne(db, key: [
            "note_id": noteId,
            "namespace": namespace,
            "key": key
        ]) ? 1 : 0
    }

    static func findByKV(
        _ db: Database,
        namespace: String,
        key: String,
        value: String? = nil,
        limit: Int = 100
    ) throws -> [(noteId: String, value: String)] {
        var request = NoteMetaRecord
            .filter(Column("namespace") == namespace && Column("key") == key)
            .order(Column("note_id"))
            .limit(limit)

        if let value {
            request = request.filter(Column("value") == value)
        }

        return try request.fetchAll(db).map { record in (noteId: record.noteId, value: record.value) }
    }
}
