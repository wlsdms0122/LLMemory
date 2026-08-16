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
// one handler needs a collaborator: dismiss_candidate has to see live lint
// findings before it may record a keep-decision, and which rules are in the
// catalog is wiring, not a constant. A table built at wiring time can hand
// that in; a static one could only let the handler reach for it.
struct HandlerRegistry: Sendable {
    // MARK: - Property
    let handlers: [String: any OperationHandling]
    
    var names: [String] { handlers.keys.sorted() }
    
    // MARK: - Initializer
    init(lint: any LintScanning) {
        handlers = [
            "create_note": CreateNoteHandler(),
            "patch_section": PatchSectionHandler(),
            "set_frontmatter": SetFrontmatterHandler(),
            "rename_section": RenameSectionHandler(),
            "flag": FlagHandler(),
            "resolve_flag": ResolveFlagHandler(),
            "dismiss_candidate": DismissCandidateHandler(lint: lint),
            "mark_used": MarkUsedHandler(),
            "set_gene": SetGeneHandler(),
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
