//
//  LinkRanking.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// How much say an edge gets when the associative surfaces rank by it. Written
// once because three neighbour queries compose it and a fourth spelling would
// discount a different set of edges than the other three.
//
// Weight and say are deliberately not the same number: a sibling edge is a
// fact the tool asserted and keeps its stored 1.0, but an N-member family
// gives every member N-1 perfect edges, and left at full voice they crowd out
// the gist. The discount takes the megaphone, not the fact.
enum LinkRanking {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func weightSQL(_ alias: String, siblingDiscount discount: Double) -> String {
        """
            (\(alias).weight * (CASE WHEN \(alias).kind = '\(LinkKind.sibling.rawValue)' \
            THEN \(discount) ELSE 1.0 END))
            """
    }

    // MARK: - Private
}
