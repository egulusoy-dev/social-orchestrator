//
//  Item.swift
//  SocialOrchestratorApp
//
//  Created by Elmir Gulusoy on 11.08.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
