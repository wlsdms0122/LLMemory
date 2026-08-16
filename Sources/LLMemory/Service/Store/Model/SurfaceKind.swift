//
//  SurfaceKind.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// How a note came to be surfaced in a retrieval — as a hit of the query
// itself, or as an expansion around one. The schema already declares this
// set closed (a CHECK on retrieval_hits.surface_kind); this is the same
// declaration on the side that writes and reads it.
enum SurfaceKind: String, Sendable {
    case hit
    case expand
}
