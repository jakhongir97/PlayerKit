//
//  UserDefaults.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 06/02/25.
//

import Foundation

extension UserDefaults {
    private static let kSelectedPlayerType = "PlayerKit.SelectedPlayerType"

    func savePlayerType(_ type: PlayerType) {
        set(type.rawValue, forKey: Self.kSelectedPlayerType)
    }

    func loadPlayerType() -> PlayerType? {
        guard let raw = string(forKey: Self.kSelectedPlayerType) else { return nil }
        return PlayerType(rawValue: raw)
    }
}
