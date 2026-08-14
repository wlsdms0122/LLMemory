//
//  LintService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// The lint domain's async door — opens a read scope and asks the scanner.
// Everything it knows about what a defect is, it knows by asking.
public struct LintService: LintServiceable {
    // MARK: - Property
    let storage: GRDBStorage
    let scanner: any LintScanning

    // MARK: - Initializer
    init(storage: GRDBStorage, scanner: any LintScanning) {
        self.storage = storage
        self.scanner = scanner
    }

    // MARK: - Public
    public func lint(
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) async throws -> [LintIssue] {
        try await storage.read { scope in
            try scanner.scan(
                scope,
                id: id,
                code: code,
                severity: severity,
                limit: limit,
                includeDismissed: includeDismissed
            )
        }
    }

    public func ruleCatalog() -> [LintRuleInfo] {
        scanner.ruleCatalog()
    }

    // MARK: - Private
}
