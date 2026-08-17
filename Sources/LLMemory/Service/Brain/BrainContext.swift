//
//  BrainContext.swift
//  LLMemory
//
//  Created by JSilver on 8/10/26.
//

import Foundation
import GRDB

// One brain, as everything about it that is not its database: where its files
// live, what its configuration says, what its genes are set to. They share a
// lifetime and an owner — a Session — and a caller that needs one of them
// usually needs another, so they travel as one value rather than as three
// that could quietly come to describe different brains.
//
// It is passed, not looked up. There was a version of this that answered from
// a task-local with a weak process-wide fallback, which meant a reader that
// forgot to bind got whichever Session had been constructed most recently —
// an answer that was right in every test and unjustifiable in principle. A
// value that arrives in a signature cannot be the wrong brain.
public struct BrainContext: Sendable {
    // MARK: - Property
    let layout: BrainLayout
    let config: Config
    let genes: Genes

    var home: URL { layout.brainRoot }

    // Both caches belong to this brain, so re-reading them belongs here too.
    // While Config owned it, the call had to be handed the other cache
    // (`config.reloadCommitted(storage, genes:)`) and nothing but the idiom
    // stopped two brains' halves being paired — the same "wrong brain
    // answered" failure the task-local used to allow, wearing a signature.
    private let cache: ParameterCache

    // MARK: - Initializer
    init(home: String) {
        let cache = ParameterCache()
        let config = Config(cache: cache)

        self.cache = cache
        layout = BrainLayout(home: home)
        self.config = config
        genes = Genes(cache: cache, config: config)
    }

    private init(layout: BrainLayout, config: Config, genes: Genes, cache: ParameterCache) {
        self.layout = layout
        self.config = config
        self.genes = genes
        self.cache = cache
    }

    // MARK: - Public
    // Re-read both caches from committed state. Run at boot and at the end of
    // every write scope, which is what keeps "the process holds what the
    // database holds" true rather than aspirational.
    //
    // Swap-only: a failed read leaves the existing values in place. Nothing
    // writes these caches inside a transaction, so they can only be behind
    // committed state, never ahead of it — an unreadable database is a reason
    // to keep the last committed values, not to drop to defaults.
    //
    // The three failures below are how a brain answers before it exists: a
    // Session is constructed against a directory the migration has not reached
    // yet, and bootstrap re-runs this once it has. Every other failure means a
    // database that was readable a moment ago no longer is, and the process is
    // about to serve values it can no longer justify — so it says so.
    func reloadCommitted(_ storage: any GRDBStorable) {
        do {
            try loadCommitted(storage)
        } catch DBError.notInitialized, DBError.pendingMigrations, DBError.superseded {
            return
        } catch {
            FileHandle.standardError.write(
                Data("llmemory: parameter cache is stale — reload failed: \(error)\n".utf8)
            )
        }
    }

    // Where a note this brain actually has lives. Existence is the only
    // thing the database is asked — the location is the id — so this pairs
    // the one question a store can answer with the one it cannot.
    func notePath(_ db: Database, _ nid: String) throws -> URL? {
        try db.run(NoteExistsTransaction(nid: nid)) ? layout.file(forId: nid) : nil
    }

    // The id of a note file this brain can index, or a refusal that says
    // which rule it broke. The address is the location, so this is the one
    // place a file becomes an id — the store is handed the answer.
    func requireNoteId(of file: URL) throws -> String {
        guard let noteId = layout.id(ofFile: file), !noteId.isEmpty else {
            throw NotesError.notALiveNote(
                path: layout.relative(of: file) ?? file.path,
                reason: layout.liveNoteRejection(of: file)
                    ?? layout.addressRejection(of: file)
                    ?? "not addressable"
            )
        }

        return noteId
    }

    // The same brain with one gene answered differently — what a shadow
    // replay runs against. It is a separate value rather than a binding, so
    // the borrowed number reaches exactly the work that was handed it.
    func shadowing(gene: String, value: Double) -> BrainContext {
        BrainContext(
            layout: layout,
            config: config,
            genes: genes.shadowing(gene, value),
            cache: cache
        )
    }

    // Plants a value the database does not hold, so a test can prove a reader
    // consults the row rather than the cache.
    func plantStaleConfigValue(_ key: String, value: String) {
        cache.plantConfigValue(key, value)
    }

    // MARK: - Private
    // One snapshot for both caches — config rows and genome values come from
    // the same read transaction, then swap in together.
    private func loadCommitted(_ storage: any GRDBStorable) throws {
        let queue = try storage.connect()
        let (configRows, genomeValues) = try queue.read { db in
            (
                try FetchConfigRowsTransaction().perform(db),
                try FetchGenomeValuesTransaction().perform(db)
            )
        }

        cache.warm(config: Config.cached(configRows), genes: genomeValues)
    }
}
