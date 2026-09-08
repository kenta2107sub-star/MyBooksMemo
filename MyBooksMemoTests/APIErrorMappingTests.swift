import Foundation
import XCTest
@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：APIError → 各FR固有のエラー種別（basic_design.md ERR-09〜17）への
// マッピングロジック（APIError.swift拡張）を検証する。外部通信を含まない純粋ロジック。
final class APIErrorMappingTests: XCTestCase {

    // MARK: - FR-04（AIChatViewModel）

    func test_chatFailureReason_networkはofflineにマッピングされる() {
        XCTAssertEqual(APIError.network.chatFailureReason, .offline)
    }

    func test_chatFailureReason_rateLimitedはrateLimitedにマッピングされる() {
        XCTAssertEqual(APIError.rateLimited.chatFailureReason, .rateLimited)
    }

    func test_chatFailureReason_その他はapiFailureにマッピングされる() {
        XCTAssertEqual(APIError.timeout.chatFailureReason, .apiFailure)
        XCTAssertEqual(APIError.serverError.chatFailureReason, .apiFailure)
        XCTAssertEqual(APIError.unauthorized.chatFailureReason, .apiFailure)
        XCTAssertEqual(APIError.decodingError.chatFailureReason, .apiFailure)
    }

    // MARK: - FR-05（SummaryViewModel）

    func test_summaryFailureReason_networkはofflineにマッピングされる() {
        XCTAssertEqual(APIError.network.summaryFailureReason, .offline)
    }

    func test_summaryFailureReason_rateLimitedはrateLimitedにマッピングされる() {
        XCTAssertEqual(APIError.rateLimited.summaryFailureReason, .rateLimited)
    }

    func test_summaryFailureReason_その他はapiFailureにマッピングされる() {
        XCTAssertEqual(APIError.timeout.summaryFailureReason, .apiFailure)
        XCTAssertEqual(APIError.serverError.summaryFailureReason, .apiFailure)
        XCTAssertEqual(APIError.unauthorized.summaryFailureReason, .apiFailure)
        XCTAssertEqual(APIError.decodingError.summaryFailureReason, .apiFailure)
    }

    // MARK: - FR-09（BookDetailViewModel）

    func test_adviceFailureReason_networkはofflineにマッピングされる() {
        XCTAssertEqual(APIError.network.adviceFailureReason, .offline)
    }

    func test_adviceFailureReason_rateLimitedはrateLimitedにマッピングされる() {
        XCTAssertEqual(APIError.rateLimited.adviceFailureReason, .rateLimited)
    }

    func test_adviceFailureReason_その他はapiFailureにマッピングされる() {
        XCTAssertEqual(APIError.timeout.adviceFailureReason, .apiFailure)
        XCTAssertEqual(APIError.serverError.adviceFailureReason, .apiFailure)
        XCTAssertEqual(APIError.unauthorized.adviceFailureReason, .apiFailure)
        XCTAssertEqual(APIError.decodingError.adviceFailureReason, .apiFailure)
    }
}

// FR-06共通ルールNo.5：許可された最小情報だけでログ文字列を組み立てることを検証する。
final class APIClientLogFormattingTests: XCTestCase {
    func test_failureLogMessage_時刻とパスとHTTPステータスだけを含む() throws {
        let url = try XCTUnwrap(
            URL(string: "https://sensitive-host.invalid/chat?query=dummy-query-secret")
        )
        var request = URLRequest(url: url)
        request.setValue("dummy-header-secret", forHTTPHeaderField: "X-Dummy-Secret")
        request.httpBody = Data(
            #"{"message":"dummy-body-secret","error":"dummy-workers-error-detail"}"#.utf8
        )

        let message = APIClient.failureLogMessage(
            path: try XCTUnwrap(request.url?.path),
            statusCode: 401,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(message, "[APIClient] 1970-01-01T00:00:00Z /chat -> HTTP 401")
        XCTAssertFalse(message.contains("https"))
        XCTAssertFalse(message.contains("sensitive-host.invalid"))
        XCTAssertFalse(message.contains("dummy-query-secret"))
        XCTAssertFalse(message.contains("dummy-header-secret"))
        XCTAssertFalse(message.contains("dummy-body-secret"))
        XCTAssertFalse(message.contains("dummy-workers-error-detail"))
    }
}
