//
//  Index.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Maintain the derived index — derive (build/vector) + verify.",
        discussion: """
            memory.db is a derived projection of the cortex/ markdown (SSoT).
            This group builds that projection and verifies it stays faithful.

              DERIVE   build   full/incremental cortex→DB sync (--path for one note)
                       vector  rebuild the algorithmic note-vector layer
              VERIFY   verify  integrity / sources / terms (see `index verify`)

            EXAMPLES
                llmemory index build --home brain
                llmemory index verify integrity --level 2 --home brain

            SEE ALSO
                index build, index verify
            """,
        subcommands: [IndexBuild.self, IndexVectors.self, IndexVerify.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct IndexVerify: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify the derived index — integrity, source drift, enrichment terms.",
        discussion: """
            Three facets of one question — is the index still valid?

                integrity   schema/row/FTS/semantic invariants (read-only)
                sources     source-file drift → source_stale (a write)
                terms       promote/reject pending retrieval terms (a write)

            SEE ALSO
                index verify integrity, index verify sources, index verify terms
            """,
        subcommands: [IndexVerifyIntegrity.self, IndexVerifySources.self, IndexVerifyTerms.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct IndexVectors: AsyncParsableCommand {
    struct VectorsOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case dim, skipped, reason
            case noteCount = "note_count"
            case builtAt = "built_at"
        }
        
        // MARK: - Property
        let noteCount: Int
        let dim: Int
        let builtAt: Int
        let skipped: Bool
        let reason: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "vector",
        abstract: "Build algorithmic dense note vectors (PPMI + truncated SVD) from the link graph.",
        discussion: """
            note_vectors are derived — no external embedding model. The same
            thing word2vec/GloVe do (factor a co-occurrence matrix), run over
            llmemory's own graph:

              1. note×note matrix — note_links weights symmetrized across kinds
                 (assoc + cooccur + reference). Notes with no links get a tag
                 Jaccard floor so no row is empty.
              2. PPMI — positive pointwise mutual information replaces raw
                 weight, discounting chance co-occurrence of busy notes. This
                 is the weighting the algorithm itself produces.
              3. truncated SVD (LAPACK dgesvd via Accelerate) → a dim-D vector
                 per note (config vectors.dim, default 48).

            Because the LLM's `assoc` edges are already in the graph, the matrix
            being factored already carries meaning — the derived vectors go
            beyond plain co-occurrence. Retrieval uses them via pseudo-relevance
            feedback (`query related` → vector_linked): the centroid of the BM25
            hits becomes a query vector, expanded by cosine to semantically near
            notes that share no keywords. If vectors are unbuilt, retrieval
            silently skips this step (graceful degradation).

            Always rebuilds when called — no skip-gate (rebuilding ~330 notes is
            microseconds, and a wall-clock/note-count gate misses link-only
            enrichment changes). Also runs as a `consolidate integrate` hook.

            EXAMPLES
                llmemory index vector --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let result = try await brain.index.buildVectors()
        let output = VectorsOutput(
            noteCount: result.noteCount,
            dim: result.dim,
            builtAt: result.builtAt,
            skipped: result.skipped,
            reason: result.reason
        )
        
        render(output, json: format.json) { output in
            [
                .text(output.skipped
                    ? "skipped: \(output.reason)"
                    : "built: \(output.noteCount) vectors, dim=\(output.dim)")
            ]
        }
    }
    
    // MARK: - Private
}

struct IndexVerifyTerms: AsyncParsableCommand {
    struct ValidateOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case activated, rejected
            case stillPending = "still_pending"
            case staleRejected = "stale_rejected"
            case rejectBreakdown = "reject_breakdown"
        }
        
        // MARK: - Property
        let activated: Int
        let rejected: Int
        let stillPending: Int
        let staleRejected: Int
        let rejectBreakdown: [String: Int]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "terms",
        abstract: "Run llmemory's own validation pass over pending retrieval terms.",
        discussion: """
            Retrieval terms (alias/cue) emitted by `operations apply add_retrieval_terms`
            land as status=pending. This pass is the gate that promotes them —
            llmemory decides, never the LLM:

              form         all-stopword / malformed terms → rejected.
              IDF (alias)  tokens whose document-frequency exceeds
                           enrich.idf_df_ceiling are too common to discriminate
                           → rejected (idf_common — the real pollution guard).
                           Tokens absent from both the corpus and the domain
                           vocab cannot be told apart from hallucination by
                           code, so they are kept pending as a quarantine —
                           never hard-rejected.
              round-trip   the term is provisionally indexed into the note's
                           enrich cell, then searched via the real FTS5
                           pipeline; the note must land in top-K (config
                           enrich.roundtrip_topk). Provisional indexing is what
                           lets a genuine synonym — one absent from the note
                           body — still activate.

            Outcomes: pass → active (indexed into notes_fts.enrich, searchable
            with zero read-time LLM cost); idf_common / malformed → rejected;
            unverifiable (quarantined) or round-trip fail → kept pending and
            retried — `--reject-stale` finalizes terms stuck pending past the
            age cutoff as rejected (aging is how an unsubstantiated quarantine
            resolves).

            `operations apply` already runs this immediately for terms it just inserted;
            `consolidate integrate` runs it periodically. Use this command to
            force a pass (e.g. after a bulk reindex changed the corpus).

            EXAMPLES
                llmemory index verify terms --home brain
                llmemory index verify terms --reject-stale --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Flag(name: .long, help: "Finalize long-pending terms as rejected (round-trip never passed).")
    var rejectStale: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let validation = try await brain.index.validateTerms(rejectStale: rejectStale)
        let result = ValidateOutput(
            activated: validation.activated,
            rejected: validation.rejected,
            stillPending: validation.stillPending,
            staleRejected: validation.staleRejected,
            rejectBreakdown: validation.rejectBreakdown
        )
        
        render(result, json: format.json) { result in
            var blocks: [PlainBlock] = [
                .text("validated: \(result.activated) activated, \(result.rejected) rejected, \(result.stillPending) still pending")
            ]
            
            if result.staleRejected > 0 {
                blocks.append(.text("stale-rejected: \(result.staleRejected)"))
            }
            
            if !result.rejectBreakdown.isEmpty {
                blocks.append(
                    .keyValue(
                        result.rejectBreakdown
                            .sorted { lhs, rhs in lhs.key < rhs.key }
                            .map { entry in (entry.key, String(entry.value)) }
                    )
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}

struct IndexBuild: AsyncParsableCommand {
    struct BuildOutput: Encodable {
        // MARK: - Property
        let count: Int
        let changed: Int
        let orphans: Int
        let errors: [String]
        let vectors: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ReindexOutput: Encodable {
        struct File: Encodable {
            enum CodingKeys: String, CodingKey {
                case path, error
                case noteId = "note_id"
                case relativePath = "relative_path"
            }

            // MARK: - Property
            // One meaning per field: `path` is always the caller-supplied
            // input path; `relativePath` (brain-root relative) exists only
            // once a reindex succeeded.
            let path: String
            let relativePath: String?
            let noteId: String?
            let error: String?

            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }

        enum CodingKeys: String, CodingKey {
            case reindexed, files
            case returnCode = "return_code"
        }

        // MARK: - Property
        let reindexed: Int
        let returnCode: Int
        let files: [File]

        var failures: [File] {
            files.filter { file in file.error != nil }
        }

        // MARK: - Initializer
        // The single partition — stderr, both render formats, and the exit
        // code all derive from this one mapping.
        init(outcomes: [Indexer.ReindexOutcome]) {
            let files = outcomes.map { outcome -> File in
                switch outcome.result {
                case .reindexed(let noteId, let relativePath):
                    return File(
                        path: outcome.filePath,
                        relativePath: relativePath,
                        noteId: noteId,
                        error: nil
                    )

                case .failure(let message):
                    return File(
                        path: outcome.filePath,
                        relativePath: nil,
                        noteId: nil,
                        error: message
                    )
                }
            }
            let failed = files.filter { file in file.error != nil }.count

            self.files = files
            self.reindexed = files.count - failed
            self.returnCode = failed == 0 ? 0 : 1
        }

        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Scan cortex/ and sync notes/tags/FTS/entity into the DB.",
        discussion: """
            Incremental by default — only changed mtimes are re-parsed. Markdown-
            derived layers (tags/FTS/reference links/entity mapping) are recomputed;
            DB-only learned/authored state (retrieval terms, cooccur/assoc edges,
            meta, flags, lifecycle, hit_count/last_retrieved) is preserved.

            --rebuild recomputes every note row from scratch (markdown is the
            SSoT), then re-derives note_vectors (the graph-derived layer) so the
            DB is left complete. DB-only learned/authored state (retrieval terms,
            cooccur/assoc edges, meta, flags, lifecycle, hit_count) is NOT lost —
            it is snapshot before the cascade and restored after, for the ids that
            come back. Use it after bulk hand-edits or schema-level resyncs.
            --path syncs only the given file(s) — single-note sync, for when a
            note was hand-edited. --path and --rebuild are mutually exclusive.
            Paths are relative to the working directory or absolute.

            EXAMPLES
                llmemory index build --home brain
                llmemory index build --rebuild --home brain
                llmemory index build --path brain/cortex/repo/foo.md --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Flag(name: .long, help: "Drop and recompute every note row, then re-derive vectors.")
    var rebuild: Bool = false
    
    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Reindex only these note path(s) instead of a full scan (single-note sync)."
    )
    var path: [String] = []
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if !path.isEmpty {
            if rebuild { throw ValidationError("--path and --rebuild are mutually exclusive") }
            
            // The scope has committed by the time outcomes return — output
            // here means committed, and the format owns the rendering.
            let output = ReindexOutput(outcomes: try await brain.index.reindex(filePaths: path))

            for failure in output.failures {
                FileHandle.standardError.write(
                    "ERROR \(failure.path): \(failure.error ?? "")\n".data(using: .utf8)!
                )
            }

            render(output, json: format.json) { output in
                output.files.compactMap { file in
                    guard let noteId = file.noteId else { return nil }

                    return .text("reindexed: \(noteId) (\(file.relativePath ?? file.path))")
                }
                + [.text("reindexed: \(output.reindexed) path(s) (rc=\(output.returnCode))")]
            }

            if output.returnCode != 0 { throw ExitCode(1) }

            return
        }
        
        let result = try await brain.index.build(rebuild: rebuild)
        
        for error in result.errors {
            FileHandle.standardError.write("ERROR \(error)\n".data(using: .utf8)!)
        }
        
        var vectors: Int? = nil
        
        if rebuild {
            do {
                vectors = try await brain.index.buildVectors().noteCount
            } catch {
                FileHandle.standardError.write(
                    "WARN vectors rebuild failed: \(error)\n".data(using: .utf8)!
                )
            }
        }
        
        let output = BuildOutput(
            count: result.count,
            changed: result.changed,
            orphans: result.orphans,
            errors: result.errors,
            vectors: vectors
        )
        
        render(output, json: format.json) { output in
            let vectorNote = output.vectors.map { count in ", vectors=\(count)" } ?? ""
            
            return [
                .text("built: \(output.count) notes (changed=\(output.changed), orphans=\(output.orphans))\(vectorNote)")
            ]
        }
        
        if !result.errors.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}

struct IndexVerifyIntegrity: AsyncParsableCommand {
    struct CheckOutput: Encodable {
        // MARK: - Property
        let ok: Bool
        let level: Int
        let messages: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "integrity",
        abstract: "Multi-level integrity check.",
        discussion: """
            Each level includes the lower ones.

            LEVELS
                0   schema shape (tables/columns/indexes match code)
                1   row presence (frontmatter ↔ DB row parity)
                2   FTS5 in sync with notes
                3   semantic checks (tag vocab, id format)
                4   (no L4 checks — derived caches removed)

            EXIT STATUS
                0   OK
                1   FAIL

            EXAMPLES
                llmemory index verify integrity --level 2 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Highest level to run (0..4, default 1).")
    var level: Indexer.IntegrityLevel = .l1
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let (ok, messages) = try await brain.index.check(level: level)
        
        render(
            CheckOutput(ok: ok, level: level.rawValue, messages: messages),
            json: format.json
        ) { output in
            [.text((output.messages + [output.ok ? "OK" : "FAIL"]).joined(separator: "\n"))]
        }
        
        if !ok { throw ExitCode(1) }
    }
    
    // MARK: - Private
}

struct IndexVerifySources: AsyncParsableCommand {
    struct VerifyOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case total, rechecked, recovered, missing, unreadable
            case stillFresh = "still_fresh"
            case becameStale = "became_stale"
        }
        
        // MARK: - Property
        let total: Int
        let rechecked: Int
        let stillFresh: Int
        let becameStale: Int
        let recovered: Int
        let missing: Int
        let unreadable: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "Recompute source fingerprints and flag drift.",
        discussion: """
            Reads each note's frontmatter `source:` paths, hashes their
            current contents, and compares with the stored baseline. Notes
            whose sources changed get source_stale=1.

            Drift signals review — it does not auto-invalidate content. Run
            periodically or before consolidate.

            EXIT STATUS
                0  every note with a baseline was checked
                1  one or more notes could not be read, so their sources were
                   not checked

            became_stale is NOT a failure: drift is the signal this command
            exists to raise, and raising it is success.

            EXAMPLES
                llmemory index verify sources --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let result = try await brain.index.verifySources()
        let output = VerifyOutput(
            total: result.total,
            rechecked: result.rechecked,
            stillFresh: result.stillFresh,
            becameStale: result.becameStale,
            recovered: result.recovered,
            missing: result.missing,
            unreadable: result.unreadable
        )
        
        render(output, json: format.json) { output -> [PlainBlock] in
            let pairs: [(String, String)] = [
                ("total", String(output.total)),
                ("rechecked (of total)", String(output.rechecked)),
                ("still_fresh (of rechecked)", String(output.stillFresh)),
                ("became_stale", String(output.becameStale)),
                ("recovered", String(output.recovered)),
                ("missing", String(output.missing)),
                ("unreadable (not checked)", String(output.unreadable.count))
            ]
            var blocks: [PlainBlock] = [.keyValue(pairs)]
            
            if !output.unreadable.isEmpty {
                blocks.append(.text(output.unreadable.joined(separator: "\n")))
            }
            
            return blocks
        }
        
        if !result.unreadable.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}

extension Indexer.IntegrityLevel: ExpressibleByArgument {
    public var defaultValueDescription: String { String(rawValue) }
    
    public init?(argument: String) {
        guard let raw = Int(argument), let level = Indexer.IntegrityLevel(rawValue: raw) else {
            return nil
        }
        
        self = level
    }
}
