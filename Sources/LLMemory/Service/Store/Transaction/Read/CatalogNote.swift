//
//  CatalogNote.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Read-surface DTOs and the catalog/list/entity/history transactions.
// Models are flat top-level types; a domain prefix disambiguates where the
// bare name could mean something else in this module (NoteListRow vs the
// genome rows, NoteView vs the NoteRecord table row). A name that
// stands alone (TocEntry, BudgetCut) stays bare — same convention as the
// service results.
struct CatalogNote: Sendable {
    // MARK: - Property
    let id: String
    let title: String
    let summary: String?
    let priority: String
    let hitCount: Int
    let createdAt: Int
    let editedAt: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
