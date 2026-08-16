//
//  IndexVectors.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

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
        
        CommandOutput().render(output, json: format.json) { output in
            [
                .text(output.skipped
                    ? "skipped: \(output.reason)"
                    : "built: \(output.noteCount) vectors, dim=\(output.dim)")
            ]
        }
    }
    
    // MARK: - Private
}
