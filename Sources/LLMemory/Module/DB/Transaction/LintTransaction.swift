//
//  LintTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct LintTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try QueryFeature.lint(connection, id: parameter.id, code: parameter.code, severity: parameter.severity, limit: parameter.limit, includeDismissed: parameter.includeDismissed)
    }
}

public extension LintTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String?
        public let code: String?
        public let severity: String?
        public let limit: Int?
        public let includeDismissed: Bool

        // MARK: - Initializer
        public init(id: String? = nil, code: String? = nil, severity: String? = nil, limit: Int? = nil, includeDismissed: Bool = false) {
            self.id = id
            self.code = code
            self.severity = severity
            self.limit = limit
            self.includeDismissed = includeDismissed
        }
    }

    typealias Result = [Lint.Issue]
}
