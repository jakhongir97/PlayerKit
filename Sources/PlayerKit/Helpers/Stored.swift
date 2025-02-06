//
//  Stored.swift
//  PlayerKit
//
//  Created by Jakhongir Nematov on 06/02/25.
//

import Foundation

@propertyWrapper
struct Stored<Value: Codable> {
    private let key: String
    private let defaultValue: Value

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let decoded = try? JSONDecoder().decode(Value.self, from: data) {
                return decoded
            }
            return defaultValue
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
}
