//
//  LinkKind.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// What an edge between two notes means. The value crosses into
// note_links.kind and comes back out, so writer and reader agree on the
// spelling here or not at all.
//
// The classifications below are total switches rather than sets. A set is a
// second list of the same vocabulary, and the way it fails is that a new kind
// is added and one of the sets is not — which compiles, and shows up as an
// edge that quietly declines to block a delete. A switch cannot be added to
// halfway.
public enum LinkKind: String, CaseIterable, Sendable {
    // MARK: - Property
    case cooccur
    case reference
    case mergeAncestor = "merge_ancestor"
    case supersedes
    case promotedTo = "promoted_to"
    case sibling
    case assoc

    // Whether the edge says the same thing read from either end. An
    // undirected pair is stored with its endpoints ordered, so the same
    // relation cannot arrive twice wearing opposite directions.
    var isUndirected: Bool {
        switch self {
        case .cooccur, .assoc, .sibling: true
        case .reference, .mergeAncestor, .supersedes, .promotedTo: false
        }
    }

    // Whether the system formed this edge by watching rather than being told.
    // Learned edges are what decay and pruning own — a fact nobody asserted
    // may fade, an asserted one may not.
    var isLearned: Bool {
        switch self {
        case .cooccur, .assoc: true
        case .reference, .mergeAncestor, .supersedes, .promotedTo, .sibling: false
        }
    }

    // Whether the edge records where a note came from. Lineage is asserted by
    // an operation, carries full weight, and is exempt from decay.
    var isLineage: Bool {
        switch self {
        case .promotedTo, .supersedes, .mergeAncestor: true
        case .cooccur, .assoc, .sibling, .reference: false
        }
    }

    // Whether an inbound edge of this kind refuses a delete. Deliberate edges
    // block because deleting the target would silently break something a
    // person or an operation asserted; learned edges do not, because they
    // describe the graph rather than depend on it.
    var blocksDelete: Bool {
        switch self {
        case .reference, .promotedTo, .supersedes, .mergeAncestor, .sibling: true
        case .cooccur, .assoc: false
        }
    }

    // MARK: - Initializer
    // MARK: - Public
    // The stored spellings of the kinds a classification admits — the form an
    // `IN (…)` list binds. Derived from the classification rather than listed
    // beside it, so the two cannot come to disagree.
    static func rawValues(where matches: (LinkKind) -> Bool) -> [String] {
        allCases.filter(matches).map { kind in kind.rawValue }
    }

    // The stored form of an edge: nothing links to itself, and an undirected
    // pair is ordered so that (a, b) and (b, a) are one row rather than two.
    func endpoints(src: String, dst: String) -> (src: String, dst: String)? {
        guard src != dst else { return nil }

        if isUndirected, src > dst { return (dst, src) }

        return (src, dst)
    }

    // MARK: - Private
}
