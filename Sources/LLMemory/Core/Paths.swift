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
    // Where the shipped innate seeds live. A dot-directory so it reads as system-owned,
    // yet its files are live notes — liveNoteRejection lets them through.
    static var innate: URL { cortexRoot.appendingPathComponent(".innate") }
    static let innateAxis = "innate"
    
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
        
        let name = file.lastPathComponent
        if name == "README.md" || name == "INDEX.md" || name == "GUIDE.md" || name.hasPrefix("_") {
            return "reserved file name: \(name)"
        }
        
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
    
    static func axisFromPath(_ path: URL) -> String {
        let relative = path.path.replacingOccurrences(of: notes.path + "/", with: "")
        let first = relative.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""

        // The innate directory is not an axis name — a seed missing its frontmatter
        // axis must still land in the innate axis, never in a ".innate" axis.
        return first == ".innate" ? innateAxis : first
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
