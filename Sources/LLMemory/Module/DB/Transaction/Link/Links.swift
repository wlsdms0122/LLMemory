//
//  Links.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public enum Links {
    // MARK: - Property
    static let kindCooccur = "cooccur"
    static let kindReference = "reference"
    static let kindMergeAncestor = "merge_ancestor"
    static let kindSupersedes = "supersedes"
    static let kindPromotedTo = "promoted_to"
    static let kindSibling = "sibling"
    static let kindAssoc = "assoc"

    static let undirectedKinds: Set<String> = [kindCooccur, kindAssoc, kindSibling]
    static let directedKinds: Set<String> = [
        kindReference, kindMergeAncestor, kindSupersedes, kindPromotedTo
    ]
    static let learnedKinds: Set<String> = [kindCooccur, kindAssoc]
    static let lineageKinds: Set<String> = [kindPromotedTo, kindSupersedes, kindMergeAncestor]
    static let deleteBlockingKinds: Set<String> = [
        kindReference, kindPromotedTo, kindSupersedes, kindMergeAncestor, kindSibling
    ]
    static let deleteNonBlockingKinds: Set<String> = learnedKinds
    static let allKinds: Set<String> = [
        kindCooccur, kindReference, kindMergeAncestor, kindSupersedes, kindPromotedTo, kindAssoc,
        kindSibling
    ]

    static var siblingRankWeight: Double {
        Genes.double("links.sibling_rank_weight")
    }

    // MARK: - Initializer
    // MARK: - Public
    static func rankWeightSQL(_ alias: String) -> String {
        "(\(alias).weight * (CASE WHEN \(alias).kind = '\(kindSibling)' THEN \(siblingRankWeight) ELSE 1.0 END))"
    }

    static func normalize(src: String, dst: String, kind: String) -> (String, String)? {
        if src == dst { return nil }
        if undirectedKinds.contains(kind) && src > dst { return (dst, src) }

        return (src, dst)
    }

    // MARK: - Private
}
