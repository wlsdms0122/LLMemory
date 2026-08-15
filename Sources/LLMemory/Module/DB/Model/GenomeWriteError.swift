//
//  GenomeWriteError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The genome surface vocabulary — flat top-level models with a domain
// prefix (owner call: a caller must not need the service's name to spell
// a return type). Errors are flat too, like CandidatesError.
public enum GenomeWriteError: Error, CustomStringConvertible {
    case unknownGene(String)
    case outOfBounds(String, Double, Genes.Gene)
    case notInteger(String, Double)
    case locked(String)

    public var description: String {
        switch self {
        case .unknownGene(let id):
            return "unknown gene: '\(id)' — see `genome list` for the catalog"

        case .outOfBounds(let id, let value, let gene):
            return "gene '\(id)' value \(value) is outside bounds [\(gene.min), \(gene.max)]"

        case .notInteger(let id, let value):
            return "gene '\(id)' takes whole numbers — got \(value)"

        case .locked(let id):
            return "gene '\(id)' is locked (write-path) — homeostasis may not adjust it"
        }
    }
}
