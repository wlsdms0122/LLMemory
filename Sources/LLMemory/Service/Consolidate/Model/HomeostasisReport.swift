//
//  HomeostasisReport.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct HomeostasisReport: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case windowsProcessed = "windows_processed"
        case expandSeen = "expand_seen"
        case expandLanded = "expand_landed"
        case sampleSeen = "sample_seen"
        case sampleLanded = "sample_landed"
        case evaluated
        case landingRate = "landing_rate"
        case adjustedGene = "adjusted_gene"
        case oldValue = "old_value"
        case newValue = "new_value"
        case note
    }

    // MARK: - Property
    public let windowsProcessed: Int
    public let expandSeen: Int
    public let expandLanded: Int
    public let sampleSeen: Int
    public let sampleLanded: Int
    public let evaluated: Bool
    public let landingRate: Double?
    public let adjustedGene: String?
    public let oldValue: Double?
    public let newValue: Double?
    public let note: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
