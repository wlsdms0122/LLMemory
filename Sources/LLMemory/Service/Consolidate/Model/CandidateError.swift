//
//  CandidateError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Raised when a caller names a candidate kind the detector does not have.
public enum CandidateError: Error, CustomStringConvertible {
    case unknownKind(String)

    public var description: String {
        switch self {
        case .unknownKind(let kind):
            return "unknown candidate kind: '\(kind)' — see candidateValidKinds"
        }
    }
}
