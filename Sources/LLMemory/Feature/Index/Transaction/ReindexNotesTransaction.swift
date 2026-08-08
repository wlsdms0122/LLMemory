//
//  ReindexNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ReindexNotesTransaction: GRDBWriteTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    // Sync body pins GRDB's synchronous write overload — execution is one connection, one thread.
    private func perform(_ connection: Connection) throws -> Result {
        var exitCode = 0

        for filePath in parameter.filePaths {
            var path = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)

            if !path.path.hasPrefix("/") {
                path = Paths.brainRoot.appendingPathComponent(filePath)
            }

            path = path.standardizedFileURL.resolvingSymlinksInPath()

            if !FileManager.default.fileExists(atPath: path.path) {
                FileHandle.standardError.write(
                    "ERROR \(filePath): not found\n".data(using: .utf8)!
                )
                exitCode = 1
                continue
            }

            if Paths.relative(of: path) == nil {
                FileHandle.standardError.write(
                    "ERROR \(filePath): outside brain home \(Paths.brainRoot.path)\n"
                        .data(using: .utf8)!
                )
                exitCode = 1
                continue
            }

            do {
                let noteId = try connection.write { db in
                    try Notes.reindexFile(db, path: path)
                }
                let relativePath = Paths.relative(of: path) ?? path.path

                print("reindexed: \(noteId) (\(relativePath))")
            } catch {
                FileHandle.standardError.write(
                    "ERROR \(filePath): \(error)\n".data(using: .utf8)!
                )
                exitCode = 1
            }
        }

        return exitCode
    }
}

public extension ReindexNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let filePaths: [String]

        // MARK: - Initializer
        public init(filePaths: [String]) {
            self.filePaths = filePaths
        }
    }

    typealias Result = Int
}
