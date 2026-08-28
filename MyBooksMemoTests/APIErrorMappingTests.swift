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
