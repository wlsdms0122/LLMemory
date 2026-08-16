//
//  Activation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

enum Activation {
    enum UsedError: Error, CustomStringConvertible {
        case notSurfaced(String)

        var description: String {
            switch self {
            case .notSurfaced(let id):
                return "note '\(id)' was not surfaced in any recent activity window — cannot mark unobserved usage"
            }
        }
    }

    // MARK: - Property
    static let watermarkKey = "activation.derive_watermark"

    // MARK: - Initializer
    // MARK: - Public
    static func windowGapSec(_ brain: BrainContext) -> Int {
        brain.genes.int("activation.window_gap_sec")
    }

    static func usedLookbackSec(_ brain: BrainContext) -> Int {
        brain.config.getInt("activation.used_lookback_sec", default: 86_400)
    }

    // MARK: - Private
}
