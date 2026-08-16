//
//  NoteFamilyIndex.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Reads fragment families out of the corpus. Family membership is decided by
// the connected components of the `sibling` edges first — those are a fact the
// tool planted — and only notes in no component at all fall back to the naming
// convention, which is our habit rather than evidence. The order matters: it
// stops members of one family that share a longer prefix from being
// reinterpreted as a phantom sub-family.
struct NoteFamilyIndex {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func families(_ scope: GRDBReadScope) throws -> [NoteFamily] {
        let minFamily = scope.brain.config.getInt("lint.fragment_min_family", default: 3)
        let graph = try scope.run(FetchFamilyGraphTransaction())
        let allIds = Set(graph.notes)
        var adjacency: [String: [String]] = [:]
        
        for link in graph.siblingLinks {
            guard allIds.contains(link.src), allIds.contains(link.dst) else { continue }
            
            adjacency[link.src, default: []].append(link.dst)
            adjacency[link.dst, default: []].append(link.src)
        }
        
        var components: [[String]] = []
        var componentOf: [String: Int] = [:]
        var visited: Set<String> = []
        
        for start in adjacency.keys.sorted() {
            guard !visited.contains(start) else { continue }
            
            var component: [String] = []
            var stack = [start]
            
            while let node = stack.popLast() {
                guard !visited.contains(node) else { continue }
                
                visited.insert(node)
                component.append(node)
                stack.append(contentsOf: adjacency[node] ?? [])
            }
            
            component.sort()
            
            for id in component { componentOf[id] = components.count }
            
            components.append(component)
        }
        
        var grouped: [String: [String]] = [:]
        
        // The naming-convention oracle, now scoped by the parent address:
        // two notes only look like siblings if they sit in the same branch.
        for id in graph.notes {
            let labels = id.split(separator: ".").map(String.init)
            
            guard let leaf = labels.last, let cut = leaf.lastIndex(of: "-") else { continue }
            
            let stem = String(leaf[leaf.startIndex..<cut])
            
            guard stem.count >= 4, stem.contains("-") else { continue }
            
            grouped["\(labels.dropLast().joined(separator: "."))\u{0}\(stem)", default: []].append(id)
        }
        
        var absorbed: [Int: Set<String>] = [:]
        var pure: [[String]] = []
        
        for (_, members) in grouped.sorted(by: { lhs, rhs in lhs.key < rhs.key }) {
            var hits: [Int: Int] = [:]
            
            for member in members {
                if let component = componentOf[member] { hits[component, default: 0] += 1 }
            }
            
            if let target = hits.max(by: { lhs, rhs in
                (lhs.value, -lhs.key) < (rhs.value, -rhs.key)
            })?.key {
                for member in members where componentOf[member] == nil {
                    absorbed[target, default: []].insert(member)
                }
            } else if members.count >= minFamily {
                pure.append(members.sorted())
            }
        }
        
        var families: [NoteFamily] = []
        
        for (index, component) in components.enumerated() {
            let members = (component + Array(absorbed[index] ?? [])).sorted()
            families.append(makeFamily(members, allIds: allIds))
        }
        
        families.append(contentsOf: pure.map { members in makeFamily(members, allIds: allIds) })
        
        return families.sorted { lhs, rhs in
            (lhs.stem ?? "", lhs.key) < (rhs.stem ?? "", rhs.key)
        }
    }
    
    func unlinkedMembers(_ scope: GRDBReadScope, _ family: NoteFamily) throws -> [String] {
        let inFamily = Set(family.members).union(family.stem.map { stem in [stem] } ?? [])
        var unlinked: [String] = []
        
        for member in family.members {
            let neighbours = try scope.run(FetchDeliberateNeighborsTransaction(noteId: member))
            
            if neighbours.contains(where: { other in inFamily.contains(other) }) { continue }
            
            unlinked.append(member)
        }
        
        return unlinked
    }
    
    // MARK: - Private
    private func makeFamily(_ members: [String], allIds: Set<String>) -> NoteFamily {
        let stem = commonStem(of: members)
        let hasIndex = stem.map { stem in allIds.contains(stem) } ?? false
        let first = members.first ?? ""
        
        return NoteFamily(
            stem: stem,
            members: members,
            hasIndex: hasIndex,
            key: hasIndex ? (stem ?? first) : first
        )
    }
    
    private func commonStem(of ids: [String]) -> String? {
        guard var prefix = ids.first else { return nil }
        
        for id in ids.dropFirst() {
            while id != prefix && !id.hasPrefix(prefix + "-") {
                guard let cut = prefix.lastIndex(of: "-") else { return nil }
                
                prefix = String(prefix[prefix.startIndex..<cut])
            }
        }
        
        guard prefix.count >= 4, prefix.contains("-") else { return nil }
        
        return prefix
    }
}
