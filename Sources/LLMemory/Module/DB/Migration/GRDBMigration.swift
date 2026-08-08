//
//  GRDBMigration.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

public protocol GRDBMigration: Sendable {
    var id: Int { get }
    var description: String? { get }

    func migrate(_ db: Database) throws
}

public extension GRDBMigration {
    var description: String? { nil }
}
