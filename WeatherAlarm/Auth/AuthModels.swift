import Foundation

struct AuthUser: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let email: String
    let displayName: String?
}

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct AuthSession: Codable, Equatable, Sendable {
    let user: AuthUser
    let tokens: AuthTokens
}

struct AuthAPIErrorResponse: Codable {
    let error: String
    let message: String?
}

enum AuthServiceError: LocalizedError {
    case missingBaseURL
    case insecureBaseURL
    case invalidResponse
    case unauthorized
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "请先在 Info.plist 的 AuthAPIBaseURL 中配置登录服务地址。"
        case .insecureBaseURL:
            return "登录服务必须使用 HTTPS。"
        case .invalidResponse:
            return "登录服务返回了无法解析的数据。"
        case .unauthorized:
            return "登录已失效，请重新登录。"
        case .serverMessage(let message):
            return message
        }
    }
}
