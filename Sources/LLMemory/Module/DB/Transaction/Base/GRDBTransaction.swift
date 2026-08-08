//
//  GRDBTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
import Storage

public protocol GRDBTransaction: DBTransaction where Connection == any DatabaseWriter { }

// Marker for transactions that mutate the database. `GRDBStorage.run` wraps these
// in the cross-process write lock (flock) that serialises concurrent CLI invocations.
public protocol GRDBWriteTransaction: GRDBTransaction { }
