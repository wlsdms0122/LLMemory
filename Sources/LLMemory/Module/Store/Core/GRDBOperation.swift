//
//  GRDBOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB
import Storage

// An operation is the DB module's vocabulary — a reusable bundle of queries
// over an open transaction.
//
// GRDB spells an open transaction `Database`, so pinning that is the whole
// refinement: a conformer declares `execute` and nothing else. What the
// operation does not carry is a commit boundary — the store opens one around
// it when it runs alone, and lends its own when the operation is composed
// into a larger one.
public protocol GRDBOperation: DBOperation where Transaction == Database { }

// An operation that only reads. It declares the fact rather than enforcing
// it: an open transaction can do either, so what this buys is the read
// connection when the operation runs on its own, and a read entry point that
// accepts nothing else. A write issued from inside a read body is a runtime
// SQLITE_READONLY, as SQLite always said it would be.
public protocol GRDBReadOperation: GRDBOperation, DBReadOperation { }
