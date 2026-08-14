//
//  IndexBuild.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

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
            
            CommandOutput().render(output, json: format.json) { output in
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
        
        CommandOutput().render(output, json: format.json) { output in
            let vectorNote = output.vectors.map { count in ", vectors=\(count)" } ?? ""
            
            return [
                .text("built: \(output.count) notes (changed=\(output.changed), orphans=\(output.orphans))\(vectorNote)")
            ]
        }
        
        if !result.errors.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
