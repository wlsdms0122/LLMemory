//
//  OperationHandling.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One op. A handler declares the fields it accepts, refuses a payload it
// cannot honour, and performs the change inside a scope the engine opened.
//
// `validate` and `write` are separate because the engine runs every
// validation before any write: a batch is one transaction, and a rejection
// found halfway would otherwise mean rolling back work already done.
//
// `effect` and `touches` describe the write without performing it — what ids
// the op brings into or takes out of the batch, and which files it would
// change so the engine can snapshot them before it starts. Most ops answer
// neither, so both have defaults; an op that answers them wrongly is worse
// than one that does not answer.
protocol OperationHandling: Sendable {
    var schema: OperationSchema { get }
    
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String?
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any]
    
    func effect(_ op: [String: Any]) -> [String: [String]]
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL]
}

extension OperationHandling {
    func effect(_ op: [String: Any]) -> [String: [String]] { [:] }
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL] { [] }
}
