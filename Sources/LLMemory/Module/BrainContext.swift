//
//  BrainContext.swift
//  LLMemory
//
//  Created by JSilver on 8/10/26.
//

import Foundation

// One brain's ambient state — the home root and the warmed parameter caches
// that Paths/Config/Genes used to keep in process globals. A Session owns
// exactly one context; the storage binds it as a task-local for the duration
// of every scope, so two live brains in one process no longer share caches.
//
// Resolution order: the task-local binding (set by storage.run/read/writeLock
// while a scope executes, and by the Index lifecycle surfaces around their
// file work) wins; outside any binding the process fallback — the most
// recently constructed, still-living Session — answers, which preserves
// single-brain ambient flows. The fallback is weak: a dead brain does not
// keep answering. Every state change (DB scope, committed-state reload,
// lifecycle file work) runs under an explicit binding.
public final class BrainContext: @unchecked Sendable {
    // MARK: - Property
    @TaskLocal static var current: BrainContext?

    // The single-brain ambient default — written at Session construction only,
    // weak so a released Session's brain stops answering instead of living on.
    nonisolated(unsafe) private static weak var fallback: BrainContext?

    static var resolved: BrainContext {
        guard let context = current ?? fallback else {
            fatalError("no brain context — a Session must be constructed first. memory CLI 는 --home 필수")
        }

        return context
    }

    let home: URL

    // The parameter caches — replaced wholesale by the committed-state loader
    // at boot and at the end of every write scope. Nothing else writes them,
    // which is what keeps them behind committed state rather than ahead of it.
    var configCache: [String: String] = [:]
    var genesCache: [String: Double] = [:]

    // MARK: - Initializer
    init(home: String) {
        let expanded = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)

        self.home = expanded.resolvingSymlinksInPath().standardized
    }

    // MARK: - Public
    // Session construction is the one writer of the ambient default.
    static func adoptFallback(_ context: BrainContext) {
        fallback = context
    }

    // Runs body with this context as the task-local binding — the storage
    // wraps every scope body (and the sync writeLock) in this.
    func bind<T>(_ body: () throws -> T) rethrows -> T {
        try BrainContext.$current.withValue(self, operation: body)
    }

    // MARK: - Private
}
