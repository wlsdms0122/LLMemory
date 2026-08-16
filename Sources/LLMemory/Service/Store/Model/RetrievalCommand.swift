//
//  RetrievalCommand.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// Which retrieval produced an event, carried in its payload under "cmd".
// The shadow replay reads the log back by this value and re-runs what it
// recognises, so writer and reader have to agree on the spelling — they
// agree here or not at all.
enum RetrievalCommand: String, Sendable {
    case search
    case related
    case neighbors
    case get
}
