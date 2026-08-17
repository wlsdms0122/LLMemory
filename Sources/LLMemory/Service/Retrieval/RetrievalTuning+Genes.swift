//
//  RetrievalTuning+Genes.swift
//  LLMemory
//
//  Created by JSilver on 8/17/26.
//

import Foundation

// Which genes the retrieval numbers come from. The bundle itself is the module's
// — the transactions take those numbers — but reading a brain's genome is a
// service's answer, so the two live apart.
extension RetrievalTuning {
    // MARK: - Initializer
    init(_ genes: Genes) {
        self.init(
            similarLimit: genes.int("related.similar_limit"),
            expandHops: genes.int("related.expand_hops"),
            neighborFloor: genes.double("links.neighbor_floor"),
            siblingDiscount: genes.double("links.sibling_rank_weight"),
            primingWindowMin: genes.int("priming.window_min"),
            primingAlpha: genes.double("priming.alpha")
        )
    }
}
