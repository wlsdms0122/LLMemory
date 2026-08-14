//
//  OperationsResultBlocks.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import LLMemory

// The plain rendering of an ops result — status, the index that was refused,
// and whatever the rollback could not put back. apply and dry-run print the
// same shape because they are the same answer at different commitment.
struct OperationsResultBlocks {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func blocks(of result: OperationsResult) -> [PlainBlock] {
        var blocks: [PlainBlock] = [
            .text(result.status == "ok"
                ? "ok  (\(result.opResults.count) ops)"
                : "\(result.status)\(result.error.isEmpty ? "" : ": \(result.error)")")
        ]
        
        if let rejectedIndex = result.rejectedIndex {
            blocks.append(.text("rejected_index: \(rejectedIndex)"))
        }
        
        if !result.recoveryFailed.isEmpty {
            blocks.append(
                .text("recovery_failed: \(result.recoveryFailed.joined(separator: ", "))")
            )
        }
        
        return blocks
    }
    
    func blocks(of result: OperationsDryRunResult) -> [PlainBlock] {
        let suffix = result.opCount.map { count in "  (\(count) ops)" } ?? ""
        var blocks: [PlainBlock] = []
        
        if let error = result.error, !error.isEmpty {
            blocks.append(.text("\(result.status): \(error)\(suffix)"))
        } else {
            blocks.append(.text("\(result.status)\(suffix)"))
        }
        
        if let rejectedIndex = result.rejectedIndex {
            blocks.append(.text("rejected_index: \(rejectedIndex)"))
        }
        
        return blocks
    }
    
    // MARK: - Private
}
