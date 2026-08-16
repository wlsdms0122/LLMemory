//
//  GeneListRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct GeneListRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, value
        case wildType = "wild_type"
        case min, max, mutable, source, summary
    }

    // MARK: - Property
    public let id: String
    public let value: Double
    public let wildType: Double
    public let min: Double
    public let max: Double
    public let mutable: Bool
    public let source: String
    public let summary: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
