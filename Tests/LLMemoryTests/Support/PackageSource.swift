//
//  PackageSource.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation

struct PackageSource {
    // MARK: - Property
    let root: URL
    
    var manifest: URL { root.appendingPathComponent("Package.swift") }
    
    // MARK: - Initializer
    init() {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        
        // Walking up to the manifest keeps every caller independent of how deep it sits in the tree.
        // A fixed number of deletingLastPathComponent() calls points at the wrong directory the
        // moment a test file moves, and an architecture guard that reads the wrong directory reports
        // "no violations" instead of "I read nothing".
        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) { break }
            
            directory = directory.deletingLastPathComponent()
        }
        
        root = directory
    }
    
    // MARK: - Public
    func file(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }
    
    func files(in relativePath: String) -> [URL] {
        let directory = root.appendingPathComponent(relativePath)
        
        // Recursive: the targets keep most of their code in nested directories, so a shallow listing
        // would let a guard pass while reading a single file.
        return FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { element in element as? URL }
            .filter { url in url.pathExtension == "swift" }
            .sorted { lhs, rhs in lhs.path < rhs.path } ?? []
    }
    
    // MARK: - Private
}
