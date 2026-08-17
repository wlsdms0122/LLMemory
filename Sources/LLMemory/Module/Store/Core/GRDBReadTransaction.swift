//
//  GRDBReadTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB
import Storage

// A transaction that only reads. It declares the fact rather than enforcing
// it: an open handle can do either, so what this buys is the read
// connection when the transaction is run on its own, the skipped savepoint
// when it is composed, and a read entry point that accepts nothing else. A
// write issued from inside a read body is a runtime SQLITE_READONLY, as
// SQLite always said it would be.
public protocol GRDBReadTransaction: GRDBTransaction { }

public extension GRDBReadTransaction {
    func execute(_ connection: any DatabaseWriter) async throws -> Result {
        try await connection.read { db in try perform(db) }
    }
}
