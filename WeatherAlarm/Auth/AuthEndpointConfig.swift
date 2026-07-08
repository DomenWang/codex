import Foundation

struct AuthEndpointConfig {
    let baseURL: URL

    init(bundle: Bundle = .main) throws {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "AuthAPIBaseURL") as? String,
              !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: rawValue) else {
            throw AuthServiceError.missingBaseURL
        }

        guard url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1" else {
            throw AuthServiceError.insecureBaseURL
        }

        self.baseURL = url
    }
}
