import XCTest
@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：FR-01（バーコードスキャン・NDL書誌取得）。
// NDL Search APIは認証不要の公開APIのため、モック化せず実際にネットワーク呼び出しを行う
// （ユーザー指示：実在するISBN 9784478025819で確認する）。
// URLProtocolStubは登録しないため、このテストクラスは実ネットワークに到達する。
final class NDLSearchServiceTests: XCTestCase {

    func test_実在するISBNで書誌情報が取得できる() async throws {
        let info = try await NDLSearchService.fetchBookInfo(isbn: "9784478025819")

        XCTAssertNotNil(info, "実在するISBNで書誌情報がnilになってはならない")
        XCTAssertFalse(info?.title.isEmpty ?? true, "タイトルが取得できていること")
        XCTAssertFalse(info?.author.isEmpty ?? true, "著者が取得できていること")
    }

    func test_存在しないISBNは検索結果0件としてnilを返す() async throws {
        // 9999999999999は割り当てられていないISBN（チェックディジット不問、検索結果0件を想定）
        let info = try await NDLSearchService.fetchBookInfo(isbn: "9999999999999")

        XCTAssertNil(info, "存在しないISBNはnil（FR-01異常系：検索結果0件）を返すこと")
    }
}
