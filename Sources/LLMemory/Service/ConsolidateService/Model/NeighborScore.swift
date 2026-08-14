//
//  NeighborScore.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct NeighborScore: Sendable {
    // MARK: - Property
    public var id: String
    public var title: String
    public var summary: String?
    public var fts: Double
    public var entity: Double
    public var link: Double
    public var score: Double
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
