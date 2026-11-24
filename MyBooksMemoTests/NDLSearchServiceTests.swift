import XCTest
@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：FR-01（バーコードスキャン・NDL書誌取得）。
// 外部APIのレート制限や応答変動をテスト結果から分離するため、URLProtocolStubで
// SRU XMLと書影レスポンスを固定し、実ネットワークへは到達させない。
final class NDLSearchServiceTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(URLProtocolStub.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(URLProtocolStub.self)
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    func test_実在するISBNで書誌情報が取得できる() async throws {
        let xml = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <searchRetrieveResponse xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <numberOfRecords>1</numberOfRecords>
          <records>
            <record>
              <recordData>
                <dcterms:title>嫌われる勇気</dcterms:title>
                <dc:creator>岸見一郎, 古賀史健著</dc:creator>
              </recordData>
            </record>
          </records>
        </searchRetrieveResponse>
        """#
        URLProtocolStub.stubs["/api/sru"] = .init(
            statusCode: 200,
            data: Data(xml.utf8),
            error: nil
        )
        URLProtocolStub.stubs["/thumbnail/9784478025819.jpg"] = .init(
            statusCode: 200,
            data: Data([0x01]),
            error: nil
        )

        let info = try await NDLSearchService.fetchBookInfo(isbn: "9784478025819")

        XCTAssertNotNil(info, "実在するISBNで書誌情報がnilになってはならない")
        XCTAssertEqual(info?.title, "嫌われる勇気")
        XCTAssertEqual(info?.author, "岸見一郎, 古賀史健")
        XCTAssertEqual(info?.coverImageData, Data([0x01]))
        XCTAssertEqual(
            URLProtocolStub.requestedPaths,
            ["/api/sru", "/thumbnail/9784478025819.jpg"]
        )
    }

    func test_存在しないISBNは検索結果0件としてnilを返す() async throws {
        let xml = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <searchRetrieveResponse>
          <numberOfRecords>0</numberOfRecords>
          <records />
        </searchRetrieveResponse>
        """#
        URLProtocolStub.stubs["/api/sru"] = .init(
            statusCode: 200,
            data: Data(xml.utf8),
            error: nil
        )

        let info = try await NDLSearchService.fetchBookInfo(isbn: "9999999999999")

        XCTAssertNil(info, "存在しないISBNはnil（FR-01異常系：検索結果0件）を返すこと")
        XCTAssertEqual(URLProtocolStub.requestedPaths, ["/api/sru"])
    }

    func test_先頭レコードに著者がない場合は後続レコードから補完しない() async throws {
        let xml = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <searchRetrieveResponse xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <records>
            <record><recordData><dcterms:title>先頭の本</dcterms:title></recordData></record>
            <record><recordData><dcterms:title>次の本</dcterms:title><dc:creator>次の著者著</dc:creator></recordData></record>
          </records>
        </searchRetrieveResponse>
        """#
        URLProtocolStub.stubs["/api/sru"] = .init(statusCode: 200, data: Data(xml.utf8), error: nil)
        URLProtocolStub.stubs["/thumbnail/9780000000001.jpg"] = .init(
            statusCode: 404,
            data: Data(),
            error: nil
        )

        let info = try await NDLSearchService.fetchBookInfo(isbn: "9780000000001")

        XCTAssertEqual(info?.title, "先頭の本")
        XCTAssertEqual(info?.author, "著者不明")
    }

    func test_先頭レコードにタイトルがない場合は後続レコードから補完しない() async throws {
        let xml = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <searchRetrieveResponse xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <records>
            <record><recordData><dc:creator>先頭の著者著</dc:creator></recordData></record>
            <record><recordData><dcterms:title>次の本</dcterms:title></recordData></record>
          </records>
        </searchRetrieveResponse>
        """#
        URLProtocolStub.stubs["/api/sru"] = .init(statusCode: 200, data: Data(xml.utf8), error: nil)

        let info = try await NDLSearchService.fetchBookInfo(isbn: "9780000000002")

        XCTAssertNil(info)
        XCTAssertEqual(URLProtocolStub.requestedPaths, ["/api/sru"])
    }

    func test_先頭レコード後にXMLが壊れている場合はnilを返す() async throws {
        let xml = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <searchRetrieveResponse xmlns:dcterms="http://purl.org/dc/terms/">
          <records>
            <record><recordData><dcterms:title>先頭の本</dcterms:title></recordData></record>
            <record><recordData><dcterms:title>閉じタグなし</recordData></record>
          </records>
        </searchRetrieveResponse>
        """#
        URLProtocolStub.stubs["/api/sru"] = .init(statusCode: 200, data: Data(xml.utf8), error: nil)

        let info = try await NDLSearchService.fetchBookInfo(isbn: "9780000000003")

        XCTAssertNil(info)
        XCTAssertEqual(URLProtocolStub.requestedPaths, ["/api/sru"])
    }
}
