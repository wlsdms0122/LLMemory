//
//  OperationsDryRunResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct OperationsDryRunResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case status
        case opCount = "op_count"
        case error
        case rejectedIndex = "rejected_index"
    }
    
    // MARK: - Property
    public let status: String
    public let opCount: Int?
    public let error: String?
    public let rejectedIndex: Int?
    
    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(status, forKey: .status)
        
        if let opCount { try container.encode(opCount, forKey: .opCount) }
        
        if let error { try container.encode(error, forKey: .error) }
        
        if let rejectedIndex { try container.encode(rejectedIndex, forKey: .rejectedIndex) }
    }
    
    // MARK: - Private
}
