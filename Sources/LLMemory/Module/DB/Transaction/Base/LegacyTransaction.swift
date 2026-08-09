//
//  LegacyReadTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
import Storage

// Read transactions see only a reader — writing from a read path is a compile
// error, not a convention.
public protocol LegacyReadTransaction: DBTransaction where Connection == any DatabaseReader { }

// Write transactions get the full writer and run under the cross-process
// write lock (flock) that serialises concurrent CLI invocations.
public protocol LegacyWriteTransaction: DBTransaction where Connection == any DatabaseWriter { }
