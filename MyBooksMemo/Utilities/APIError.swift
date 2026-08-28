import Foundation

/// FR-06共通ルールNo.4（エラーメッセージのトーン統一）に対応する共通エラー型。
/// 各ViewModelはこの型を受け取り、FR固有の文言（ERR-09〜17）にマッピングする。
enum APIError: Error {
    case timeout          // URLSessionのタイムアウト（10秒/15秒超過）
    case network          // ネットワーク接続なし（NWPathMonitorで事前判定 or URLError.notConnectedToInternet）
    case unauthorized      // HTTP 401（X-Shared-Secret不一致）
    case rateLimited       // HTTP 429
    case serverError       // HTTP 500（Gemini呼び出し失敗・タイムアウト・NF-03のレスポンス形式異常）
    case decodingError     // HTTP 400、またはレスポンスJSONのデコード失敗
}

extension APIError {
    /// FR-04（AIChatViewModel）向けマッピング
    var chatFailureReason: ChatPreviewError {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
    /// FR-05（SummaryViewModel）向けマッピング
    var summaryFailureReason: SummaryFailureReason {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
    /// FR-09（BookDetailViewModel）向けマッピング
    var adviceFailureReason: AdviceFailureReason {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
}
