//
//  Index.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Index {
    public struct InitResult {
        // MARK: - Property
        public let homePath: String
        public let dataExisted, cortexExisted, dbExisted: Bool
        public let indexed, changed: Int
        public let errors: [String]
        public let seeding: Seeding.Result
        
        public var alreadyInitialized: Bool { dataExisted || cortexExisted || dbExisted }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct UpdateResult {
        // MARK: - Property
        public let homePath: String
        public let seeding: Seeding.Result
        public let indexed, changed: Int
        public let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // Session stays for the lifecycle gates (bootstrap) — init/update are the
    // migration surface, not a domain service.
    let session: Session
    let service: IndexService

    // MARK: - Initializer
    init(session: Session, service: IndexService) {
        self.session = session
        self.service = service
    }
    
    public func build(rebuild: Bool = false) async throws -> Indexer.BuildResult {
        try await service.build(rebuild: rebuild)
    }

    @discardableResult
    public func reindex(filePaths: [String]) async throws -> [Indexer.ReindexOutcome] {
        try await service.reindex(filePaths: filePaths)
    }

    public func check(level: Indexer.IntegrityLevel = .l1) async throws -> (ok: Bool, msgs: [String]) {
        try await service.check(level: level)
    }

    public func buildVectors() async throws -> VectorBuildResult {
        try await service.buildVectors()
    }

    public func verifySources() async throws -> SourceVerifyResult {
        try await service.verifySources()
    }

    public func validateTerms(rejectStale: Bool) async throws -> Indexer.ValidateResult {
        try await service.validateTerms(rejectStale: rejectStale)
    }
    
    // Lifecycle work touches the filesystem outside any scope — the session's
    // context is bound explicitly so a second live brain cannot steal these
    // writes through the ambient fallback.
    public func initialize(base: Bool = true) throws -> InitResult {
        try session.context.bind { try initializeBound(base: base) }
    }

    private func initializeBound(base: Bool) throws -> InitResult {
        let fileManager = FileManager.default
        let dataExisted = fileManager.fileExists(atPath: Paths.dataDirectory.path)
        let cortexExisted = fileManager.fileExists(atPath: Paths.cortexRoot.path)
        let dbExisted = fileManager.fileExists(atPath: Paths.db.path)
        
        try fileManager.createDirectory(at: Paths.dataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: Paths.cortexRoot, withIntermediateDirectories: true)
        
        let seeding = base ? Seeding.plant() : Seeding.Result()
        let result = try session.bootstrap()
        
        try Guide.markdown.write(
            to: Paths.brainRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        
        return InitResult(
            homePath: Paths.brainRoot.path,
            dataExisted: dataExisted,
            cortexExisted: cortexExisted,
            dbExisted: dbExisted,
            indexed: result.count,
            changed: result.changed,
            errors: result.errors + seeding.errors,
            seeding: seeding
        )
    }
    
    public func update(base: Bool = true) throws -> UpdateResult {
        try session.context.bind { try updateBound(base: base) }
    }

    private func updateBound(base: Bool) throws -> UpdateResult {
        let seeding = base ? Seeding.plant() : Seeding.Result()

        // update is the migration surface: a brain left behind by a binary upgrade
        // is carried forward by the bootstrap, before anything else touches the
        // connection.
        let result = try session.bootstrap()

        try Guide.markdown.write(
            to: Paths.brainRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        
        return UpdateResult(
            homePath: Paths.brainRoot.path,
            seeding: seeding,
            indexed: result.count,
            changed: result.changed,
            errors: result.errors + seeding.errors
        )
    }
    
    
}
