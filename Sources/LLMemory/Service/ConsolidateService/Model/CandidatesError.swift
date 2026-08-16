//
//  CandidatesError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The restructuring detector — what counts as a candidate (split shapes,
// stale flags, clusters, missing edges, near-duplicates) is decided here;
// row access rides candidate transactions in Module/DB.
//
// The Service tier's line: an XxxService instance is an effectful surface
// over storage (owns the async doors, gets wired by the container); a
// policy namespace like CandidateDetector/Lint is pure judgment vocabulary over a
// scope — stateless, shared by whichever services need it (Consolidate
// dispatches batches, Retrieval scores neighbors).
public enum CandidatesError: Error, CustomStringConvertible {
    case unknownKind(String)

    public var description: String {
        switch self {
        case .unknownKind(let kind):
            return "unknown candidate kind: '\(kind)' — see candidateValidKinds"
        }
    }
}
