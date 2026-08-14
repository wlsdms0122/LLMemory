//
//  SeedingSummary.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// One reading of what seeding did, for every command that does it. `init` and
// `update` run the same reconciliation, and when each wrote its own summary they
// drifted — one of them grew a `retired` line and the other went on calling a run
// that moved files "already current".
struct SeedingSummary: Sendable {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func blocks(
        attempted: Bool,
        planted: [String],
        refreshed: [String],
        unchanged: [String],
        retired: [String],
        replaced: [String],
        conflicts: [String]
    ) -> [PlainBlock] {
        guard attempted else { return [.text("seed notes: skipped (--no-seed)")] }
        
        if !conflicts.isEmpty {
            return [
                .text(
                    "CONFLICT: these addresses hold notes that do not carry `seed: true`, so "
                        + "nothing was planted — move them aside, or rerun with --force to send "
                        + "them to .trash/ and take the address:\n  "
                        + conflicts.joined(separator: "\n  ")
                )
            ]
        }
        
        let moved = planted + refreshed + retired + replaced
        
        guard !moved.isEmpty else {
            return [.text("seed notes: already current (\(unchanged.count) unchanged)")]
        }
        
        return [
            .keyValue([
                ("planted", list(planted)),
                ("refreshed", list(refreshed)),
                ("unchanged", list(unchanged)),
                ("retired", list(retired)),
                ("replaced", list(replaced))
            ])
        ]
    }
    
    // MARK: - Private
    private func list(_ ids: [String]) -> String {
        ids.isEmpty ? "-" : ids.joined(separator: ", ")
    }
}
