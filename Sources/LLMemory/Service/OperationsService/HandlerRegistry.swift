//
//  HandlerRegistry.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The op vocabulary — every op name this build accepts, bound to the handler
// that answers it.
//
// It is assembled per engine rather than held as a type-level table, because
// two handlers need a collaborator: set_gene writes through genome, and
// dismiss_candidate has to see live lint findings before it may record a
// keep-decision. A table built at wiring time can hand those in; a static one
// could only let the handlers reach for them.
struct HandlerRegistry: Sendable {
    // MARK: - Property
    let handlers: [String: any OperationHandling]

    var names: [String] { handlers.keys.sorted() }

    // MARK: - Initializer
    init(genome: any GenomeServiceable, lint: any LintScanning) {
        handlers = [
            "create_note": CreateNoteHandler(),
            "patch_section": PatchSectionHandler(),
            "set_frontmatter": SetFrontmatterHandler(),
            "rename_section": RenameSectionHandler(),
            "flag": FlagHandler(),
            "resolve_flag": ResolveFlagHandler(),
            "dismiss_candidate": DismissCandidateHandler(lint: lint),
            "mark_used": MarkUsedHandler(),
            "set_gene": SetGeneHandler(genome: genome),
            "invalidate": InvalidateHandler(),
            "revalidate": RevalidateHandler(),
            "rebase_source": RebaseSourceHandler(),
            "restore": RestoreHandler(),
            "delete_note": DeleteNoteHandler(),
            "migrate_note": MigrateNoteHandler(),
            "rename_tag": RenameTagHandler(),
            "relocate_section": RelocateSectionHandler(),
            "split_note": SplitNoteHandler(),
            "merge_notes": MergeNotesHandler(),
            "add_retrieval_terms": AddRetrievalTermsHandler(),
            "propose_link": ProposeLinkHandler(),
            "link_lineage": LinkLineageHandler(),
            "purge_enrichment": PurgeEnrichmentHandler()
        ]
    }

    // MARK: - Public
    subscript(name: String) -> (any OperationHandling)? { handlers[name] }

    // MARK: - Private
}
