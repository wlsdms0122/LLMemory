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
        // nil when the seeds were not attempted (--no-seed). An empty result
        // means they were attempted and there was nothing to do, and those are
        // different things to report.
        public let seeding: Seeding.Result?

        public var alreadyInitialized: Bool { dataExisted || cortexExisted || dbExisted }
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct UpdateResult {
        // MARK: - Property
        public let homePath: String
        // nil when the seeds were not attempted (--no-seed).
        public let seeding: Seeding.Result?
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
    let service: any IndexServiceable

    private let seeding: Seeding

    // MARK: - Initializer
    init(session: Session, service: any IndexServiceable) {
        self.session = session
        self.service = service
        seeding = Seeding(layout: session.context.layout)
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
    
    public func initialize(seed: Bool = true, force: Bool = false) throws -> InitResult {
        let fileManager = FileManager.default
        let dataExisted = fileManager.fileExists(atPath: session.context.layout.dataDirectory.path)
        let cortexExisted = fileManager.fileExists(atPath: session.context.layout.cortexRoot.path)
        let dbExisted = fileManager.fileExists(atPath: session.context.layout.db.path)
        
        try fileManager.createDirectory(at: session.context.layout.dataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: session.context.layout.cortexRoot, withIntermediateDirectories: true)
        
        // Planted inside the bootstrap: after the migration, before the build.
        var seeding: Seeding.Result?
        let result = try session.bootstrap { db in
            if seed { seeding = try plant(force: force, db: db) }
        }

        try Guide.markdown.write(
            to: session.context.layout.brainRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        
        return InitResult(
            homePath: session.context.layout.brainRoot.path,
            dataExisted: dataExisted,
            cortexExisted: cortexExisted,
            dbExisted: dbExisted,
            indexed: result.count,
            changed: result.changed,
            errors: result.errors + (seeding?.errors ?? []),
            seeding: seeding
        )
    }
    
    public func update(seed: Bool = true, force: Bool = false) throws -> UpdateResult {
        // update is the migration surface: a brain left behind by a binary upgrade
        // is carried forward by the bootstrap, before anything else touches the
        // connection — and before the seeds are restated, so a brain whose schema
        // did not move forward does not get files that did.
        var seeding: Seeding.Result?
        let result = try session.bootstrap { db in
            if seed { seeding = try plant(force: force, db: db) }
        }

        try Guide.markdown.write(
            to: session.context.layout.brainRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        
        return UpdateResult(
            homePath: session.context.layout.brainRoot.path,
            seeding: seeding,
            indexed: result.count,
            changed: result.changed,
            errors: result.errors + (seeding?.errors ?? [])
        )
    }

    // MARK: - Private
    private func plant(force: Bool, db: BootstrapScope) throws -> Seeding.Result {
        seeding.plant(
            force: force,
            seeded: try db.seededNoteIds(),
            now: Int(Date().timeIntervalSince1970),
            db: db
        )
    }
}
