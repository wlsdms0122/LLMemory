//
//  LintScanning.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Judgement over a scope somebody else opened. It owns no storage: given a
// read scope it runs the catalog, drops what a person has reviewed and kept,
// and says which codes are answerable at all.
//
// It is separate from LintServiceable because the two are different jobs. The
// service opens a scope and asks; the scanner is asked. Folding them together
// is what made the dismiss_candidate handler — which only ever asks — depend
// on a type that also owns a database handle.
protocol LintScanning: Sendable {
    var dismissibleCodes: Set<String> { get }
    var errorCodes: Set<String> { get }

    func ruleCatalog() -> [LintRuleInfo]

    func scan(
        _ scope: GRDBReadScope,
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) throws -> [LintIssue]
}
