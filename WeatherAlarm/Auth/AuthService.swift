import Foundation

final class AuthService {
    private let session: URLSession
    private let configProvider: () throws -> AuthEndpointConfig
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: URLSession = .shared,
        configProvider: @escaping () throws -> AuthEndpointConfig = { try AuthEndpointConfig() }
    ) {
        self.session = session
        self.configProvider = configProvider
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        try await send(
            path: "/auth/login",
            method: "POST",
            body: CredentialsRequest(email: email, password: password),
            authorization: nil
        )
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AuthSession {
        try await send(
            path: "/auth/register",
            method: "POST",
            body: RegisterRequest(email: email, password: password, displayName: displayName),
            authorization: nil
        )
    }

    func currentUser(accessToken: String) async throws -> AuthUser {
        try await send(
            path: "/auth/me",
            method: "GET",
            body: Optional<EmptyRequest>.none,
            authorization: accessToken
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        try await send(
            path: "/auth/refresh",
            method: "POST",
            body: LogoutRequest(refreshToken: refreshToken),
            authorization: nil
        )
    }

    func logout(refreshToken: String) async throws {
        let _: EmptyResponse = try await send(
            path: "/auth/logout",
            method: "POST",
            body: LogoutRequest(refreshToken: refreshToken),
            authorization: nil
        )
    }

    private func makeRequest<T: Encodable>(
        path: String,
        method: String,
        body: T?,
        authorization: String?
    ) throws -> URLRequest {
        let config = try configProvider()
        let url = config.baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        path: String,
        method: String,
        body: RequestBody?,
        authorization: String?
    ) async throws -> ResponseBody {
        let request = try makeRequest(path: path, method: method, body: body, authorization: authorization)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw AuthServiceError.unauthorized
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(AuthAPIErrorResponse.self, from: data) {
                throw AuthServiceError.serverMessage(apiError.message ?? apiError.error)
            }
            throw AuthServiceError.invalidResponse
        }

        if ResponseBody.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseBody
        }

        do {
            return try decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }
}

private struct CredentialsRequest: Encodable {
    let email: String
    let password: String
}

private struct RegisterRequest: Encodable {
    let email: String
    let password: String
    let displayName: String?
}

private struct LogoutRequest: Encodable {
    let refreshToken: String
}

private struct EmptyRequest: Encodable {}

private struct EmptyResponse: Codable {}
