//
//  Trash.swift
//  LLMemory
//
//  Created by JSilver on 8/14/26.
//

import Foundation

// Removal is a move, never an erase — cortex/.trash/ keeps the file and its body
// until a person decides. Nothing here knows why a note is going; the reason is
// recorded on the note and the caller supplies it.
//
// It lives in the Module tier because it is filesystem and markdown and nothing
// else: ops trash notes a person deleted, and update trashes notes the release
// stopped shipping, and neither is more entitled to the mechanism than the other.
public struct Trash: Sendable {
    // MARK: - Property
    private let paths: Paths

    private let frontmatter = Frontmatter()

    private let noteFiles = Notes()

    // MARK: - Initializer
    init(paths: Paths) {
        self.paths = paths
    }

    // MARK: - Public
    public func pathFor(_ relativePath: String) throws -> URL {
        paths.trash.appendingPathComponent(try relativeToNotes(relativePath))
    }

    // A name already taken in the trash means an earlier note went by the same
    // address; both are kept, told apart by a counter.
    public func resolvePath(_ relativePath: String) throws -> URL {
        let base = try pathFor(relativePath)

        if !FileManager.default.fileExists(atPath: base.path) { return base }

        let directory = base.deletingLastPathComponent()
        let pathExtension = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var counter = 1

        while true {
            let candidate = directory.appendingPathComponent(
                pathExtension.isEmpty ? "\(stem).\(counter)" : "\(stem).\(counter).\(pathExtension)"
            )

            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }

            counter += 1
        }
    }

    @discardableResult
    public func file(_ source: URL, reason: String, now: Int) throws -> URL? {
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }

        let relativePath = try noteFiles.relativeToBrainRoot(source, paths)
        var (doc, body) = try frontmatter.parse(try String(contentsOf: source, encoding: .utf8))
        doc.trashedAt = now
        doc.trashedReason = reason.unicodeScalarPrefix(200)

        let trashPath = try resolvePath(relativePath)

        try FileManager.default.createDirectory(
            at: trashPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (frontmatter.dump(doc) + body).write(to: trashPath, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: source)

        return trashPath
    }

    // Where a file would land, for the snapshot that has to be able to put it back.
    public func destination(of source: URL) -> URL? {
        guard let relativePath = try? noteFiles.relativeToBrainRoot(source, paths) else { return nil }

        return try? resolvePath(relativePath)
    }

    // MARK: - Private
    private func relativeToNotes(_ relativePath: String) throws -> String {
        let absolutePath = paths.brainRoot.appendingPathComponent(relativePath).path
        let notesPrefix = paths.notes.path + "/"

        guard absolutePath.hasPrefix(notesPrefix) else {
            throw NSError(domain: "Trash", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "not under cortex/: \(relativePath)"
            ])
        }

        return String(absolutePath.dropFirst(notesPrefix.count))
    }
}
