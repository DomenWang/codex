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

struct EntitlementSyncPayload: Codable, Equatable, Sendable {
    let hasPurchasedForever: Bool
    let isWeatherSubscribed: Bool
    let hasGaodeEnhance: Bool
    let weatherExpireDate: Date?
    let gaodeExpireDate: Date?
    let productIDs: [String]
    let transactionIDs: [String]
    let originalTransactionIDs: [String]
    let capturedAt: Date?
    let clientSyncedAt: Date
}

struct EntitlementSyncRequest: Codable, Equatable, Sendable {
    let userID: UUID
    let payload: EntitlementSyncPayload
}

struct EntitlementSyncResponse: Codable, Equatable, Sendable {
    let syncedAt: Date
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
            return "登录服务暂未开启，请稍后再试。"
        case .insecureBaseURL:
            return "登录服务暂时不可用，请稍后再试。"
        case .invalidResponse:
            return "登录没有成功，请稍后再试。"
        case .unauthorized:
            return "登录已失效，请重新登录。"
        case .serverMessage(let message):
            return message
        }
    }
}
