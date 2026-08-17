//
//  GRDBTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB
import Storage

// A transaction is the DB module's vocabulary — a reusable bundle of
// queries over a database handle.
//
// It is a DBTransaction, and `perform` is what makes that possible. The
// protocol's own entry point is async, which a caller inside GRDB's
// synchronous write block cannot await; `perform` is the same work with
// the handle already open, so composition happens through it and nothing
// in the sync path ever touches the async requirement.
//
// The two are not two designs. `execute` is `perform` with the unit of
// work opened around it — which is exactly what running a transaction on
// its own means — so a transaction claims no atomicity of its own and
// composes into any unit of work, however it was entered.
// The two associated types are pinned here because nothing else could infer
// them: Parameter is named by no requirement DBTransaction has, and
// Connection is not what `perform` takes. Pinned, a conformer declares
// `perform` and nothing else.
public protocol GRDBTransaction: DBTransaction where Connection == any DatabaseWriter, Parameter == Never {
    // Restated so that naming a transaction's result does not oblige every
    // file that holds one to import the module the name came from — and so
    // that the constraints above have a requirement to resolve against.
    associatedtype Result

    @discardableResult
    func perform(_ db: Database) throws -> Result
}

public extension GRDBTransaction {
    @discardableResult
    func execute(_ connection: any DatabaseWriter) async throws -> Result {
        try await connection.write { db in try perform(db) }
    }
}
