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
        // Drift was found and --override was not given — the innate space was left alone.
        public let blocked: Bool
        // Foreign files --override removed to match the shipped set.
        public let removed: [String]
        public let indexed, changed: Int
        public let errors: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let session: Session
    
    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }
    
    public func build(rebuild: Bool = false) async throws -> Indexer.BuildResult {
        try await IndexService.build(session.storage, rebuild: rebuild)
    }

    @discardableResult
    public func reindex(filePaths: [String]) async throws -> Int {
        try await IndexService.reindex(session.storage, filePaths: filePaths)
    }

    public func check(level: Indexer.IntegrityLevel = .l1) async throws -> (ok: Bool, msgs: [String]) {
        try await IndexService.check(session.storage, level: level)
    }

    public func buildVectors() async throws -> Vectors.BuildResult {
        try await IndexService.buildVectors(session.storage)
    }

    public func verifySources() async throws -> SourcesService.BulkVerifyResult {
        try await IndexService.verifySources(session.storage)
    }

    public func validateTerms(rejectStale: Bool) async throws -> Indexer.ValidateResult {
        try await IndexService.validateTerms(session.storage, rejectStale: rejectStale)
    }
    
    public func initialize(bare: Bool = false) throws -> InitResult {
        let fileManager = FileManager.default
        let dataExisted = fileManager.fileExists(atPath: Paths.dataDirectory.path)
        let cortexExisted = fileManager.fileExists(atPath: Paths.cortexRoot.path)
        let dbExisted = fileManager.fileExists(atPath: Paths.db.path)
        
        try fileManager.createDirectory(at: Paths.dataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: Paths.cortexRoot, withIntermediateDirectories: true)
        
        // init is deliberate setup — presence of .innate/ is not consulted, only --bare is.
        let seeding = bare ? Seeding.Result() : Seeding.plant(mode: .missingOnly, force: true)
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
    
    // Report-only classification of the innate space against the shipped copy — what
    // update would plant/refresh/relocate/skip — without touching a single file.
    public func checkSeeds(force: Bool = false) -> Seeding.Result {
        Seeding.plant(mode: .overwrite, force: force, dryRun: true)
    }

    public func update(override: Bool = false) throws -> UpdateResult {
        // Classify first without writing. Any drift means human state is in the way —
        // update warns and leaves the innate space alone; only --override restates it
        // to exactly the shipped set (removing foreign files too). An absent space
        // (opted out) is not drift — it is skipped quietly.
        var seeding = Seeding.plant(mode: .overwrite, force: override, dryRun: true)
        var blocked = false
        var removed: [String] = []

        if override {
            seeding = Seeding.plant(mode: .overwrite, force: true)
            removed = Seeding.removeForeign()
            seeding.foreign = []
        } else if seeding.drift {
            blocked = true
        }

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
            blocked: blocked,
            removed: removed,
            indexed: result.count,
            changed: result.changed,
            errors: result.errors + seeding.errors
        )
    }
    
    
}
