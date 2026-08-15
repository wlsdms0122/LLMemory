//
//  EventKind.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// What an event row records. Closed by nature — the readers of the log
// (window derivation, tag priors, shadow replay) branch on this value, so a
// kind nobody reads is not a kind, and a kind spelled two ways is a row
// they silently skip.
enum EventKind: String, Encodable, Sendable {
    case capture
    case consolidation
    case retrieval
}
