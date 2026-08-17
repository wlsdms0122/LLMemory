//
//  EnrichmentStatus.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct EnrichmentStatus: Sendable {
    public struct ProvenanceStat: Sendable {
        // MARK: - Property
        public let provenance: String
        public let assocEdges: Int
        public let disagreeEdges: Int

        public var disagreeRate: Double {
            assocEdges > 0 ? Double(disagreeEdges) / Double(assocEdges) : 0
        }

        // The threshold is a configured judgement, so it arrives with the
        // question rather than being fetched from wherever this row is read.
        public func alarm(over rate: Double) -> Bool {
            disagreeRate > rate
        }

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    public let termCounts: [(kind: String, status: String, count: Int)]
    public let assocTotal: Int
    public let assocActive: Int
    public let assocDormant: Int
    public let vectorsBuiltAt: Int?
    public let vectorsDim: Int?
    public let noteCount: Int
    public let vectorCount: Int
    public let provenanceStats: [ProvenanceStat]
    public let reviewFlagged: Int
    // The rate above which a provenance is worth looking at. It is this
    // brain's judgement, so it is reported with the numbers it judges rather
    // than fetched again wherever they are rendered.
    public let modelAlarmRate: Double

    public var vectorCoverage: Double {
        noteCount > 0 ? Double(vectorCount) / Double(noteCount) : 0
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
