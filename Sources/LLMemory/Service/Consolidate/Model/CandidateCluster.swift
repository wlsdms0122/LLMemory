//
//  CandidateCluster.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct CandidateCluster: Sendable {
    public struct Edge: Sendable {
        // MARK: - Property
        public let a: String
        public let b: String
        public let fts: Double
        public let entity: Double
        public let link: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    public let size: Int
    public let members: [CandidateMember]
    public let edges: [Edge]
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
