//
//  HandlerContext.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct HandlerContext {
    // MARK: - Property
    // The batch's ambient facts — resolved once at the apply/dry-run entry
    // so no handler re-derives them from process globals. The initializer
    // requires them: an unseeded context does not compile.
    public let sessionId: SessionId?
    public let now: Int

    // The brain this batch runs against — where its files live and what its
    // configuration says. Handlers take it from here rather than from the
    // scope they write through: a scope is a database handle, and a handle
    // that also answered "where does note x live" was the store's way of
    // knowing things only the domain should know.
    let brain: BrainContext
    
    public var inFlightIds: Set<String> = []
    public var invalidatedIds: Set<String> = []
    public var removedIds: Set<String> = []
    public var lockedInFlightIds: Set<String> = []
    public var stagedBodies: [String: String] = [:]
    public var opaqueBodyIds: Set<String> = []
    
    // MARK: - Initializer
    init(sessionId: SessionId?, now: Int, brain: BrainContext) {
        self.sessionId = sessionId
        self.now = now
        self.brain = brain
    }
    
    // MARK: - Public
    // MARK: - Private
}
