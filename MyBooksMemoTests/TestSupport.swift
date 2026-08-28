@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：本体（APIError.swift）はEquatable準拠を持たないため、
// テストでのXCTAssertEqual比較のためにテスト側でのみ準拠させる（本体コードは変更しない）。
extension APIError: Equatable {
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.timeout, .timeout),
             (.network, .network),
             (.unauthorized, .unauthorized),
             (.rateLimited, .rateLimited),
             (.serverError, .serverError),
             (.decodingError, .decodingError):
            return true
        default:
            return false
        }
    }
}
