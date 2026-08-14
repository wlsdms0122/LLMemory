//
//  Genes.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GenomeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "genome",
        abstract: "Plasticity-parameter catalog — per-brain values, history, shadow introspection.",
        discussion: """
            The genome is the substrate's parameter layer made data. The
            *declaration* (which genes exist, bounds, wild-type, mutability) is
            code — species-level and versioned with the binary. The *per-brain
            current value* (epigenome) lives in the genome table; a gene without
            a row runs at wild-type.

            Two write doors only:
              · set_gene op (`operations apply`) — direct value set, all genes.
              · consolidate homeostasis — deterministic loop, mutable
                (read-path) genes only.

            SEE ALSO
                genome list, genome history, genome shadow
                consolidate homeostasis, operations describe set_gene
            """,
        subcommands: [GenomeList.self, GenomeHistory.self, GenomeShadow.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
