import CadenceCore
import Foundation

/// Cadence's own backend. No other project's endpoints, keys, or tables.
public actor SyncClient {
    public static let shared = SyncClient()

    /// Set in Cadence.xcconfig — never hardcode.
    private var baseURL: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "CADENCE_API_URL") as? String).flatMap(URL.init)
    }
    private var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "CADENCE_API_KEY") as? String
    }

    public func upload(summary: SessionSummary, frames: [Frame]) async {
        guard let baseURL, let apiKey else { return }
        struct Payload: Encodable { let summary: SessionSummary; let frames: [Frame] }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard let body = try? enc.encode(Payload(summary: summary, frames: frames)) else { return }

        var req = URLRequest(url: baseURL.appendingPathComponent("api/sessions"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        _ = try? await URLSession.shared.data(for: req)
    }
}
