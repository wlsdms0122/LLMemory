//
//  Migration2.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// notes.seed — 배포본의 씨드에서 심긴 노트라는 출처 표시 (frontmatter 파생).
// 전용 디렉터리가 없으므로 init/update 가 "이 주소가 배포본 것인가"를 이걸로 가른다.
// ops 는 못 쓴다.
//
// Added as a migration rather than by editing the baseline: the baseline is what
// an already-migrated brain will never run again, so growing it there grows only
// the schema of brains that do not exist yet. The shape gate compares the DDL a
// full catalog run produces, and a catalog run ends the same way on both — the
// baseline CREATE with this column appended — so a fresh brain and a migrated one
// agree by construction.
public struct Migration2: GRDBMigration {
    // MARK: - Property
    public var id: Int { 2 }
    public var description: String? { "notes.seed — shipped-copy provenance" }

    // MARK: - Initializer
    // MARK: - Public
    public func migrate(_ db: Database) throws {
        let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(notes)")
            .map { row in row["name"] as String }

        guard !columns.contains("seed") else { return }

        try db.execute(
            sql: "ALTER TABLE notes ADD COLUMN seed INTEGER NOT NULL DEFAULT 0 CHECK (seed IN (0,1))"
        )
    }

    // MARK: - Private
}
