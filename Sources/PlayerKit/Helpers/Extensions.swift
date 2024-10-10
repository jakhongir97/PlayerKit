//
//  Extensions.swift
//  PlayerKitDemo
//
//  Created by Jakhongir Nematov on 08/10/24.
//

import Foundation

// Add a safe subscript for collections to avoid index out of range errors
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
