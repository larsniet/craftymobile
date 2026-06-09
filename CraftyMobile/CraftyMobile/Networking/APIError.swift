//
//  APIError.swift
//  CraftyMobile
//
//  A single error type for everything the networking layer can surface, with
//  user-facing messages. The goal is that *no* failure crashes the app — each
//  case maps to a friendly inline banner.
//

import Foundation

enum APIError: LocalizedError, Equatable {
    case notConfigured                 // missing base URL or token
    case invalidURL(String)
    case unauthorized                  // 401 / 403 — bad or expired token
    case tlsTrust                      // certificate could not be trusted
    case server(status: Int, message: String?)
    case apiError(String)              // status: "error" with a message
    case decoding(String)
    case transport(String)             // generic URLSession failure
    case offline                       // no network connectivity

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set your server URL and API token in Settings first."
        case .invalidURL(let url):
            return "The server URL isn’t valid: \(url)"
        case .unauthorized:
            return "Authentication failed. Check your API token in Settings — it may be wrong or expired."
        case .tlsTrust:
            return "Couldn’t verify the server’s certificate. If you use a self-signed cert, enable “Allow self-signed certificates” in Settings."
        case .server(let status, let message):
            if let message, !message.isEmpty {
                return "Server error (\(status)): \(message)"
            }
            return "Server returned an error (HTTP \(status))."
        case .apiError(let message):
            return message.isEmpty ? "The server reported an error." : message
        case .decoding:
            return "Got an unexpected response from the server."
        case .transport(let message):
            return "Network error: \(message)"
        case .offline:
            return "You appear to be offline."
        }
    }
}
