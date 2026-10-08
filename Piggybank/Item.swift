//
//  Item.swift
//  Piggybank
//
//  Created by Donald A Stibich on 10/7/26.
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
