//
//  NoteMetaTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// note_meta side-table transactions — namespaced key/value rows per note.
struct FetchNoteMetaValueTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let namespace: String
    let key: String

    // MARK: - Initializer
    init(noteId: String, namespace: String, key: String) {
        self.noteId = noteId
        self.namespace = namespace
        self.key = key
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String? {
        try NoteMetaRecord.fetchOne(db, key: [
            "note_id": noteId,
            "namespace": namespace,
            "key": key
        ])?
            .value
    }

    // MARK: - Private
}

struct FetchNoteMetaTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let namespace: String?

    // MARK: - Initializer
    init(noteId: String, namespace: String? = nil) {
        self.noteId = noteId
        self.namespace = namespace
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: [String: String]] {
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

    // MARK: - Private
}

struct UpsertNoteMetaTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let namespace: String
    let key: String
    let value: String
    let now: Int

    // MARK: - Initializer
    init(noteId: String, namespace: String, key: String, value: String, now: Int) {
        self.noteId = noteId
        self.namespace = namespace
        self.key = key
        self.value = value
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try NoteMetaRecord(
            noteId: noteId,
            namespace: namespace,
            key: key,
            value: value,
            updatedAt: now
        )
            .upsert(db)
    }

    // MARK: - Private
}

struct DeleteNoteMetaTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let namespace: String
    let key: String

    // MARK: - Initializer
    init(noteId: String, namespace: String, key: String) {
        self.noteId = noteId
        self.namespace = namespace
        self.key = key
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        try NoteMetaRecord.deleteOne(db, key: [
            "note_id": noteId,
            "namespace": namespace,
            "key": key
        ]) ? 1 : 0
    }

    // MARK: - Private
}

struct FindNoteMetaByKVTransaction: GRDBTransaction {
    // MARK: - Property
    let namespace: String
    let key: String
    let value: String?
    let limit: Int

    // MARK: - Initializer
    init(namespace: String, key: String, value: String? = nil, limit: Int = 100) {
        self.namespace = namespace
        self.key = key
        self.value = value
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(noteId: String, value: String)] {
        var request = NoteMetaRecord
            .filter(Column("namespace") == namespace && Column("key") == key)
            .order(Column("note_id"))
            .limit(limit)

        if let value {
            request = request.filter(Column("value") == value)
        }

        return try request.fetchAll(db).map { record in (noteId: record.noteId, value: record.value) }
    }

    // MARK: - Private
}
