//
//  OpVocabulary.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The closed vocabularies of the op language — the values an op may name, as
// opposed to the free text it may carry. Nothing here is behaviour, so it is a
// constant table and stays one: a handler reads the accepted set, it does not
// negotiate with it.
public enum OpVocabulary {
    // MARK: - Property
    public static let tagRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*$"#)
    public static let headingMarkerRegex = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*$"#)
    
    public static let validPriority: Set<String> = ["eager", "lazy"]
    public static let creatableFlagKinds: Set<String> = ["reconsolidate", "stale_ref"]
    public static let resolvableFlagKinds: Set<String> = creatableFlagKinds.union(["enrich_review"])
    public static let validPatchActions: Set<String> = ["replace", "append", "prepend", "remove"]
    // Frontmatter is the SSoT of a note's knowledge, so set_frontmatter is open by
    // default: any key it does not recognise lands in `extra` and is projected to
    // note_extra. Only the fields below stay closed — each is either identity/path
    // (moved by migrate_note), a lifecycle state owned by its own op, or human-only.
    // Fields ops may not author. `seed` is here because it is the note's claim
    // to be a planted copy — a note that could grant itself that claim could
    // arrange to be overwritten by the next release, which is the one thing the
    // claim exists to decide.
    public static let frontmatterReserved: Set<String> = [
        "id", "template", "seed", "locked",
        "stale", "invalidated_at", "invalidated_reason",
        "trashed_at", "trashed_reason"
    ]
    public static let extraKeyRegex = try! NSRegularExpression(pattern: #"^[A-Za-z_]\w*$"#)
}
