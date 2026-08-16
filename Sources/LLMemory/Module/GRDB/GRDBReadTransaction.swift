//
//  GRDBReadTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// A transaction that only reads — the read scope accepts these alone, so
// writing from a read path is a compile error again, not a runtime
// SQLITE_READONLY surprise.
public protocol GRDBReadTransaction: GRDBTransaction { }
