//
//  SchemaShape.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

// L0 schema verification — compares a live database against the shape the
// migration catalogue produces on a pristine in-memory database. Consumed by
// `migrate` (init/update gate) and `index verify`.
public struct SchemaShape {
    // MARK: - Property
    private let migrations: [any GRDBMigration]

    // MARK: - Initializer
    public init(migrations: [any GRDBMigration]) {
        self.migrations = migrations
    }

    // MARK: - Public
    public func check(_ db: Database) throws -> [String] {
        var messages: [String] = []
        let expected = try expectedShape()
        let expectedDDL = try withPristineDatabase { pristine in
            try Self.storedDDL(pristine)
        }
        let actualDDL = try Self.storedDDL(db)

        for (name, expectedSQL) in expectedDDL.sorted(by: { lhs, rhs in lhs.key < rhs.key }) {
            guard let actualSQL = actualDDL[name] else { continue }

            if actualSQL != expectedSQL {
                messages.append("L0\tddl-mismatch\t\(name)\t(CHECK/FK/FTS/type definition differs from code schema)")
            }
        }

        let actualTables = Set(try Self.tableNames(db))
        let expectedTables = Set(expected.keys)

        for table in expectedTables.subtracting(actualTables).sorted() {
            messages.append("L0\ttable-missing\t\(table)")
        }

        for table in actualTables.subtracting(expectedTables).sorted() {
            messages.append("L0\ttable-unexpected\t\(table)")
        }

        for table in expectedTables.intersection(actualTables).sorted() {
            let expectedShape = expected[table]!
            let columnRows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
            let actualColumns = Set(columnRows.map { row in row["name"] as String })
            let actualIndexes = Set(try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='index'
                AND tbl_name=? AND name NOT LIKE 'sqlite_%'
                """, arguments: [table]))

            for column in expectedShape.columns.subtracting(actualColumns).sorted() {
                messages.append("L0\tcolumn-missing\t\(table).\(column)")
            }

            for column in actualColumns.subtracting(expectedShape.columns).sorted() {
                messages.append("L0\tcolumn-unexpected\t\(table).\(column)")
            }

            for index in expectedShape.indexes.subtracting(actualIndexes).sorted() {
                messages.append("L0\tindex-missing\t\(table).\(index)")
            }

            for index in actualIndexes.subtracting(expectedShape.indexes).sorted() {
                messages.append("L0\tindex-unexpected\t\(table).\(index)")
            }
        }

        return messages
    }

    public func expectedShape() throws -> [String: (columns: Set<String>, indexes: Set<String>)] {
        try withPristineDatabase { db in
            var shape: [String: (columns: Set<String>, indexes: Set<String>)] = [:]

            for table in try Self.tableNames(db) {
                let columnRows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                let columns = Set(columnRows.map { row in row["name"] as String })
                let indexes = Set(try String.fetchAll(
                    db,
                    sql: """
                    SELECT name FROM sqlite_master WHERE type='index'
                    AND tbl_name=? AND name NOT LIKE 'sqlite_%'
                    """,
                    arguments: [table]
                ))
                shape[table] = (columns, indexes)
            }

            return shape
        }
    }

    public static func normalizedSQL(_ sql: String) -> String {
        var stripped: [String] = []

        for line in sql.split(separator: "\n", omittingEmptySubsequences: false) {
            var text = String(line)

            if let comment = text.range(of: "--") { text = String(text[..<comment.lowerBound]) }

            stripped.append(text)
        }

        return stripped.joined(separator: " ")
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*([(),])\s*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private
    private func withPristineDatabase<T>(_ body: (Database) throws -> T) throws -> T {
        var migrator = DatabaseMigrator()

        migrations.sorted { lhs, rhs in lhs.id < rhs.id }
            .forEach { migration in
                migrator.registerMigration("\(migration.id)") { db in
                    try migration.migrate(db)
                }
            }

        let memory = try DatabaseQueue()
        try migrator.migrate(memory)

        return try memory.read(body)
    }

    private static func tableNames(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: """
            SELECT name FROM sqlite_master
            WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'notes_fts%'
            """
        )
    }

    private static func storedDDL(_ db: Database) throws -> [String: String] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT name, sql FROM sqlite_master
            WHERE type='table' AND name NOT LIKE 'sqlite_%'
              AND (name NOT LIKE 'notes_fts_%')
            """)
        var ddl: [String: String] = [:]

        for row in rows {
            guard let sql: String = row["sql"] else { continue }

            ddl[row["name"]] = normalizedSQL(sql)
        }

        return ddl
    }
}
