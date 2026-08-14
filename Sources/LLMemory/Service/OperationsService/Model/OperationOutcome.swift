//
//  OperationOutcome.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The operations result vocabulary — flat top-level models with a domain
// prefix (owner call). OperationOutcome is one op's verdict inside an
// OperationsResult batch — the names differ by role, not by one letter.
public struct OperationOutcome: Encodable, Sendable {
    // MARK: - Property
    public let op: String
    public let status: String
    public let note: String
    public let paths: [String]
    public let ids: [String]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
