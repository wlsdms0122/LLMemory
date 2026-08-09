//
//  GetSectionsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct GetSectionsTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.getSections(connection, id: parameter.id, sections: parameter.sections)
    }
}

public extension GetSectionsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String
        public let sections: [String]

        // MARK: - Initializer
        public init(id: String, sections: [String]) {
            self.id = id
            self.sections = sections
        }
    }

    typealias Result = (note: Reads.GetNote, slices: [Reads.SectionSlice], record: RecordRetrievalTransaction.Parameter?)
}
