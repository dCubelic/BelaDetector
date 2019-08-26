//
//  BelaPrediction.swift
//  BelaDetector
//
//  Created by Dominik Cubelic on 05/08/2019.
//  Copyright © 2019 Dominik Cubelic. All rights reserved.
//

import UIKit

struct BelaPrediction: Hashable {
    let card: BelaCard
    let confidence: Float
    let rect: CGRect
    
    init(classIndex: Int, confidence: Float, rect: CGRect) {
        self.card = BelaCard.cards[classIndex]
        self.confidence = confidence
        self.rect = rect
    }
}

extension CGRect: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        
    }
    
}
