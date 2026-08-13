//
//  Paths.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// Path vocabulary over the bound brain home — every value resolves through
// BrainContext, so the answers follow whichever brain's scope is executing.
enum Paths {
    // MARK: - Property
    static var brainRoot: URL { root() }
    static var dataDirectory: URL { root().appendingPathComponent("data") }
    
    static var db: URL { dataDirectory.appendingPathComponent("memory.db") }
    
    static var cortexRoot: URL { root().appendingPathComponent("cortex") }
    static var notes: URL { cortexRoot }
    static var trash: URL { cortexRoot.appendingPathComponent(".trash") }
    // Where the shipped innate seeds live. An ordinary branch of the address
    // space — being shipped is a fact about where a note came from, not about
    // where it sits, so nothing here is special-cased.
    static let innateBranch = "innate"
    static var innate: URL { cortexRoot.appendingPathComponent(innateBranch) }

    // An id is labels joined by dots, and the dots are directory separators.
    static let idRegex = try! NSRegularExpression(pattern: #"^[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)*$"#)

    // MARK: - Initializer
    
    // MARK: - Public
    static func relative(of file: URL) -> String? {
        let abs = canonical(file)
        let root = canonical(brainRoot)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        
        guard abs.hasPrefix(prefix) else { return nil }
        
        return String(abs.dropFirst(prefix.count))
    }
    
    static func liveNoteRejection(of file: URL) -> String? {
        guard let relative = relative(of: file) else {
            return "outside brain home \(brainRoot.path)"
        }
        
        let components = relative.split(separator: "/").map(String.init)
        
        guard components.first == "cortex" else { return "not under cortex/" }
        
        guard file.pathExtension == "md" else { return "not a .md note file" }

        // No file name under cortex/ is reserved — everything there is knowledge.
        // A name that cannot be an id is not skipped either: it is scanned and
        // then fails the id syntax loudly, because a knowledge file that the walk
        // silently steps over is a knowledge file the brain does not have.
        if components.count > 1, components[1] == ".trash" {
            return "under cortex/.trash — a trashed note comes back through the restore op, not by reindexing in place"
        }
        
        if components.count > 1, components[1] == ".archive" {
            return "under cortex/.archive"
        }
        
        return nil
    }
    
    static func scanNotes() -> [URL] {
        let fileManager = FileManager.default
        let notesRoot = root().appendingPathComponent("cortex")
        
        guard fileManager.fileExists(atPath: notesRoot.path) else { return [] }
        
        var notes: [URL] = []
        
        guard let iterator = fileManager.enumerator(
            at: notesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }
        
        for case let url as URL in iterator {
            let resolved = url.standardized
            
            if liveNoteRejection(of: resolved) != nil {
                continue
            }
            
            notes.append(resolved)
        }
        
        return notes
    }
    
    // The address is the location. `a.b.c` lives at `cortex/a/b/c.md`, and the
    // two functions below are inverses — nothing about a note's whereabouts is
    // stored, so nothing about it can drift out of agreement with itself.
    static func file(forId id: String) -> URL {
        let labels = id.split(separator: ".").map(String.init)

        return labels.dropLast()
            .reduce(notes) { url, label in url.appendingPathComponent(label) }
            .appendingPathComponent("\((labels.last ?? id)).md")
    }

    // The brain-relative spelling of the same address — what output surfaces
    // show and what callers used to read off the removed column.
    static func relativeFile(forId id: String) -> String {
        let file = file(forId: id)

        return relative(of: file) ?? file.path
    }

    // One definition of what a prefix is, because three quietly different ones
    // is how two fields of the same response come to disagree.
    static func labels(of id: String) -> [String] {
        id.split(separator: ".").map(String.init)
    }

    // The ancestor of `id` that is `depth` labels long, or nil if the id is
    // shorter than that. `branch(of: "a.b.c", depth: 1)` is "a".
    static func branch(of id: String, depth: Int) -> String? {
        let labels = labels(of: id)

        guard labels.count >= depth, depth > 0 else { return nil }

        return labels.prefix(depth).joined(separator: ".")
    }

    // At or under: the address itself is part of its own branch. Everything that
    // aggregates over a branch means this — a note at `a.b` is as much a member
    // of a.b as `a.b.c` is.
    static func id(_ id: String, isWithin prefix: String) -> Bool {
        id == prefix || id.hasPrefix(prefix + ".")
    }

    // Strictly the inverse of file(forId:), verified rather than assumed. A dot
    // inside a file name would otherwise make the pair many-to-one — cortex/a/b.c.md
    // and cortex/a/b/c.md both spell a.b.c — and with the address as the only id,
    // two files sharing one would mean one of them silently overwriting the other.
    static func id(ofFile file: URL) -> String? {
        guard let relative = relative(of: file) else { return nil }

        let components = relative.split(separator: "/").map(String.init)

        guard components.first == "cortex", components.count > 1,
            let name = components.last, name.hasSuffix(".md")
        else {
            return nil
        }

        var labels = Array(components.dropFirst())
        labels[labels.count - 1] = String(name.dropLast(3))

        let id = labels.joined(separator: ".")

        guard canonical(self.file(forId: id)) == canonical(file) else { return nil }

        return id
    }

    // Why a file cannot be addressed, for the surfaces that must not skip it quietly.
    static func addressRejection(of file: URL) -> String? {
        guard id(ofFile: file) == nil else { return nil }

        return "no address: a path label may not contain '.' "
            + "(\(relative(of: file) ?? file.path))"
    }

    static func canonicalPath(_ url: URL) -> String { canonical(url) }

    // The SQL spelling of "the first `depth` labels of this id". Aggregation
    // belongs in SQLite — a hit log only grows — so the definition is shared as
    // an expression rather than by pulling rows out to group them in Swift.
    static func branchSQL(column: String, depth: Int = 1) -> String {
        precondition(depth == 1, "only the first label has a SQL spelling today")

        return """
            CASE WHEN instr(\(column), '.') > 0
                 THEN substr(\(column), 1, instr(\(column), '.') - 1)
                 ELSE \(column) END
            """
    }

    // MARK: - Private
    private static func root() -> URL {
        BrainContext.resolved.home
    }
    
    private static func canonical(_ url: URL) -> String {
        let path = url.standardized.path
        for aliased in ["/tmp", "/var", "/etc"] {
            let privatized = "/private" + aliased
            
            if path == privatized {
                return aliased
            }
            
            if path.hasPrefix(privatized + "/") {
                return aliased + String(path.dropFirst(privatized.count))
            }
        }
        
        return path
    }
}
