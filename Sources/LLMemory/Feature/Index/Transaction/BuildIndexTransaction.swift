//
//  BuildIndexTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct BuildIndexTransaction: GRDBWriteTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Index.build(rebuild: parameter.rebuild)
    }
}

public extension BuildIndexTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let rebuild: Bool

        // MARK: - Initializer
        public init(rebuild: Bool = false) {
            self.rebuild = rebuild
        }
    }

    typealias Result = Index.BuildResult
}
