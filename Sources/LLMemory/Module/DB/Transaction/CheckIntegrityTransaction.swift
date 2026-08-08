//
//  CheckIntegrityTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct CheckIntegrityTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Index.check(connection, rawLevel: parameter.level.rawValue)
    }
}

public extension CheckIntegrityTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let level: Index.IntegrityLevel

        // MARK: - Initializer
        public init(level: Index.IntegrityLevel = .l1) {
            self.level = level
        }
    }

    typealias Result = (ok: Bool, msgs: [String])
}
