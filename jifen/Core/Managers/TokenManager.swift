//
//  TokenManager.swift
//  jifen
//
//  Placeholder token manager
//

import Foundation

/// Placeholder token manager
class TokenManager {
    static let shared = TokenManager()
    
    private init() {}
    
    var token: String? {
        get {
            return UserDefaults.standard.string(forKey: "auth_token")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "auth_token")
        }
    }
    
    func clearToken() {
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }
    
    func hasValidToken() -> Bool {
        return token != nil
    }
}

