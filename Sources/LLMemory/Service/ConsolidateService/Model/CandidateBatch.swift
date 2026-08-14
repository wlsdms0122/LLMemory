//
//  CandidateBatch.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public enum CandidateBatch: Sendable {
    case split([SplitCandidate])
    case flagged([FlaggedCandidate])
    case clusters([CandidateCluster])
    case missingEdge([MissingEdge])
    case nearDuplicate([NearDuplicate])
    
    public var count: Int {
        switch self {
        case .split(let items):
            return items.count
        
        case .flagged(let items):
            return items.count
        
        case .clusters(let items):
            return items.count
        
        case .missingEdge(let items):
            return items.count
        
        case .nearDuplicate(let items):
            return items.count
        }
    }
}
