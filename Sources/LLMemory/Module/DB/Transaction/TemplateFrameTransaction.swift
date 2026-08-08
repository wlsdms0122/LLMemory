//
//  TemplateFrameTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct TemplateFrameTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.template(connection, id: parameter.id)
    }
}

public extension TemplateFrameTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String

        // MARK: - Initializer
        public init(id: String) {
            self.id = id
        }
    }

    typealias Result = (note: Reads.GetNote, frame: [Template.FrameNode])
}
