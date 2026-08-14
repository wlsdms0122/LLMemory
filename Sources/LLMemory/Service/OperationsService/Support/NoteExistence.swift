//
//  NoteExistence.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Whether an id names a note, counting the ones this batch is about to create.
// A batch is one transaction, so an op may refer to a note an earlier op in the
// same payload creates — the catalog alone would call that unknown.
struct NoteExistence {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func state(_ scope: GRDBReadScope) throws -> ExistingState {
        ExistingState(ids: try scope.run(FetchNoteIdsTransaction()))
    }
    
    func rejectionForUnknown(
        _ nid: String,
        context: HandlerContext,
        scope: GRDBReadScope
    ) throws -> String? {
        if context.inFlightIds.contains(nid) { return nil }
        if try scope.run(NoteExistsTransaction(nid: nid)) { return nil }
        
        return "unknown id: \(nid)"
    }
    
    // MARK: - Private
}
