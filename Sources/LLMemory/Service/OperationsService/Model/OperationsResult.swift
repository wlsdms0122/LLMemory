//
//  OperationsResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct OperationsResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case status, rationale, conflict
        case opResults = "ops"
        case error
        case rejectedIndex = "rejected_index"
        case recoveryFailed = "recovery_failed"
        case degradedPasses = "degraded_passes"
    }
    
    // MARK: - Property
    public let status: String
    public let opResults: [OperationOutcome]
    public let error: String
    public let rejectedIndex: Int?
    public let rationale: String
    public let recoveryFailed: [String]
    public let conflict: SplitConflict?
    // Best-effort passes that failed and rolled back, by name — the
    // caller distinguishes "nothing to do" from "pass degraded" without
    // digging through the event log. Error detail lives in the trace
    // event, keeping this a stable pass-name vocabulary.
    public let degradedPasses: [String]
    
    // MARK: - Initializer
    public init(
        status: String,
        opResults: [OperationOutcome],
        error: String,
        rejectedIndex: Int?,
        rationale: String,
        recoveryFailed: [String],
        conflict: SplitConflict? = nil,
        degradedPasses: [String] = []
    ) {
        self.status = status
        self.opResults = opResults
        self.error = error
        self.rejectedIndex = rejectedIndex
        self.rationale = rationale
        self.recoveryFailed = recoveryFailed
        self.conflict = conflict
        self.degradedPasses = degradedPasses
    }
    
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(status, forKey: .status)
        try container.encode(rationale, forKey: .rationale)
        try container.encode(opResults, forKey: .opResults)
        
        if !error.isEmpty { try container.encode(error, forKey: .error) }
        
        if let rejectedIndex { try container.encode(rejectedIndex, forKey: .rejectedIndex) }
        
        if !recoveryFailed.isEmpty {
            try container.encode(recoveryFailed, forKey: .recoveryFailed)
        }
        
        if let conflict { try container.encode(conflict, forKey: .conflict) }
        
        if !degradedPasses.isEmpty {
            try container.encode(degradedPasses, forKey: .degradedPasses)
        }
    }
    
    // MARK: - Private
}
