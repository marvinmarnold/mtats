// SPDX-License-Identifier: MIT
import Foundation

public struct PublicIPFetcher {
    private static let endpoints = ["https://api.ipify.org", "https://icanhazip.com"]

    /// Pure parsing: a valid response is exactly one IPv4 address, nothing else.
    public static func parse(responseBody: String) -> String? {
        let trimmed = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ part in
            guard let value = Int(part) else { return false }
            return value >= 0 && value <= 255
        }) else { return nil }
        return trimmed
    }

    /// Tries each endpoint in order, falling back on failure. Returns nil if all fail
    /// (Review Focus: offline/blocked must degrade to "unavailable", never crash or hang).
    public static func fetch(urlSession: URLSession = .shared) async -> String? {
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            if let (data, response) = try? await urlSession.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let body = String(data: data, encoding: .utf8),
               let ip = parse(responseBody: body) {
                return ip
            }
        }
        return nil
    }
}
