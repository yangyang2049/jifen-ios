//
//  HttpClient.swift
//  jifen
//
//  Placeholder HTTP client for future implementation
//

import Foundation

/// Placeholder HTTP client
class HttpClient {
    static let shared = HttpClient()
    
    private init() {}
    
    func request<T: Codable>(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> T {
        // Placeholder implementation
        throw NSError(domain: "HttpClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP client not implemented"])
    }
}

