//
//  Paths.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// Where one brain keeps its files. Every value here is relative to a home,
// which is what separates it from NoteAddress: the grammar of an id needs no
// brain, and the location of the note it names needs nothing else.
struct Paths: Sendable {
    // MARK: - Property
    let brainRoot: URL

    var dataDirectory: URL { brainRoot.appendingPathComponent("data") }
    var db: URL { dataDirectory.appendingPathComponent("memory.db") }

    var cortexRoot: URL { brainRoot.appendingPathComponent("cortex") }
    var notes: URL { cortexRoot }
    var trash: URL { cortexRoot.appendingPathComponent(".trash") }

    // MARK: - Initializer
    // A home is taken as written and resolved once, so two spellings of the
    // same directory cannot become two brains.
    init(home: String) {
        let expanded = URL(fileURLWithPath: (home as NSString).expandingTildeInPath)

        brainRoot = expanded.resolvingSymlinksInPath().standardized
    }

    // MARK: - Public
    func relative(of file: URL) -> String? {
        let abs = canonical(file)
        let root = canonical(brainRoot)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        
        guard abs.hasPrefix(prefix) else { return nil }
        
        return String(abs.dropFirst(prefix.count))
    }
    
    // The same answer as relative(of:), for callers that cannot carry on
    // without one — a file outside this brain is not a file it can name.
    func requireRelative(of file: URL) throws -> String {
        guard let relativePath = relative(of: file) else {
            throw NotesError.notUnderBrainRoot(file.path)
        }

        return relativePath
    }

    func liveNoteRejection(of file: URL) -> String? {
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
    
    func scanNotes() -> [URL] {
        let fileManager = FileManager.default
        let notesRoot = cortexRoot
        
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
    
    // The address is the location. `a.b.c` lives at `cortex/a/b/c.md`, and
    // file(forId:)/id(ofFile:) are inverses — nothing about a note's
    // whereabouts is stored, so nothing about it can drift out of agreement
    // with itself.
    func file(forId id: String) -> URL {
        let labels = NoteAddress.labels(of: id)

        return labels.dropLast()
            .reduce(notes) { url, label in url.appendingPathComponent(label) }
            .appendingPathComponent("\((labels.last ?? id)).md")
    }

    // The brain-relative spelling of the same address — what output surfaces
    // show and what callers used to read off the removed column.
    func relativeFile(forId id: String) -> String {
        let file = file(forId: id)

        return relative(of: file) ?? file.path
    }

    // Strictly the inverse of file(forId:), verified rather than assumed. A dot
    // inside a file name would otherwise make the pair many-to-one — cortex/a/b.c.md
    // and cortex/a/b/c.md both spell a.b.c — and with the address as the only id,
    // two files sharing one would mean one of them silently overwriting the other.
    func id(ofFile file: URL) -> String? {
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
    func addressRejection(of file: URL) -> String? {
        guard id(ofFile: file) == nil else { return nil }

        return "no address: a path label may not contain '.' "
            + "(\(relative(of: file) ?? file.path))"
    }

    func canonicalPath(_ url: URL) -> String { canonical(url) }

    // MARK: - Private
    private func canonical(_ url: URL) -> String {
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
