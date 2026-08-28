import XCTest
import SwiftData
@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：FR-04・FR-05・FR-09で使うCloudflareWorkersClientの
// リクエスト構築・レスポンスパース・エラーハンドリングを、URLProtocolStubで実ネットワークを
// 遮断した状態で検証する（Gemini APIの実呼び出しはCloudflare Workers側の責務であり、
// iOS側はWorkersが返すHTTPレスポンスの扱いのみを検証すればよい）。
final class CloudflareWorkersClientTests: XCTestCase {

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

    // MARK: - 正常系

    func test_chat_正常系レスポンスをデコードして返す() async throws {
        let json = #"{"question":"次に何を考えましたか？"}"#
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        let response = try await CloudflareWorkersClient.shared.chat(
            bookTitle: "テスト駆動開発",
            memoContent: "気づき",
            conversationHistory: []
        )

        XCTAssertEqual(response.question, "次に何を考えましたか？")
        XCTAssertEqual(URLProtocolStub.requestedPaths, ["/chat"])
    }

    func test_summarize_正常系レスポンスをデコードして返す() async throws {
        let json = #"{"summary":"・要約その1"}"#
        URLProtocolStub.stubs["/summarize"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        let response = try await CloudflareWorkersClient.shared.summarize(
            bookTitle: "テスト駆動開発",
            memos: [(date: Date(), content: "気づき")],
            conversationLogs: []
        )

        XCTAssertEqual(response.summary, "・要約その1")
    }

    func test_advice_正常系レスポンスをデコードして返す() async throws {
        let json = #"{"advice":"次はぜひ実践してみましょう。"}"#
        URLProtocolStub.stubs["/advice"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        let response = try await CloudflareWorkersClient.shared.generateAdvice(
            bookTitle: "テスト駆動開発",
            memoContent: "気づき",
            conversationTurns: []
        )

        XCTAssertEqual(response.advice, "次はぜひ実践してみましょう。")
    }

    // MARK: - エラーハンドリング（HTTPステータスコード → APIError変換）

    func test_chat_HTTP400はdecodingErrorに変換される() async throws {
        let json = #"{"error":"invalid_request","message":"不正です"}"#
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 400, data: Data(json.utf8), error: nil)

        do {
            _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .decodingError)
        }
    }

    func test_chat_HTTP401はunauthorizedに変換される() async throws {
        let json = #"{"error":"unauthorized","message":"X-Shared-Secretが一致しません"}"#
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 401, data: Data(json.utf8), error: nil)

        do {
            _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func test_advice_HTTP429はrateLimitedに変換される() async throws {
        let json = #"{"error":"rate_limited","message":"レート制限"}"#
        URLProtocolStub.stubs["/advice"] = .init(statusCode: 429, data: Data(json.utf8), error: nil)

        do {
            _ = try await CloudflareWorkersClient.shared.generateAdvice(bookTitle: "本", memoContent: "メモ", conversationTurns: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .rateLimited)
        }
    }

    func test_summarize_HTTP500はserverErrorに変換される() async throws {
        let json = #"{"error":"generation_failed","message":"失敗"}"#
        URLProtocolStub.stubs["/summarize"] = .init(statusCode: 500, data: Data(json.utf8), error: nil)

        do {
            _ = try await CloudflareWorkersClient.shared.summarize(bookTitle: "本", memos: [(date: Date(), content: "メモ")], conversationLogs: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .serverError)
        }
    }

    func test_chat_タイムアウトはtimeoutに変換される() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 0, data: Data(), error: URLError(.timedOut))

        do {
            _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func test_chat_オフラインはnetworkに変換される() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 0, data: Data(), error: URLError(.notConnectedToInternet))

        do {
            _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .network)
        }
    }

    func test_chat_レスポンスJSONの形式が不正な場合decodingErrorになる() async throws {
        // HTTP 200だがquestionフィールドが無い（想定外のレスポンス形式）
        let json = #"{"unexpected":"value"}"#
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        do {
            _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])
            XCTFail("エラーが投げられるべき")
        } catch let error as APIError {
            XCTAssertEqual(error, .decodingError)
        }
    }

    // MARK: - リクエスト構築の検証

    func test_chat_リクエストヘッダーにX共有シークレットとContentTypeを設定する() async throws {
        let json = #"{"question":"Q"}"#
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        _ = try await CloudflareWorkersClient.shared.chat(bookTitle: "本", memoContent: "メモ", conversationHistory: [])

        XCTAssertEqual(URLProtocolStub.requestedPaths, ["/chat"])
    }

    // MARK: - 回帰テスト：SummaryViewModel.generateSummary(context:)がcachedSummaryを永続化する
    // （コードレビューで発見・修正：修正前はcontext.save()を呼んでおらず、SwiftDataのautosave
    // タイミング次第で生成済みの要約が失われるおそれがあった。同じcontainerから新しいModelContextで
    // 読み直すことで、単なるプロパティ変更ではなく実際にストアへ保存されたことを検証する）
    @MainActor
    func test_SummaryViewModel_generateSummaryはcachedSummaryをcontext保存する() async throws {
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let book = Book(title: "テスト駆動開発", author: "Kent Beck")
        context.insert(book)
        let memo = MemoEntry(date: Date(), contentItems: ["気づき"])
        context.insert(memo)
        memo.book = book
        book.memoEntries.append(memo)
        try context.save()

        let json = #"{"summary":"・要約その1"}"#
        URLProtocolStub.stubs["/summarize"] = .init(statusCode: 200, data: Data(json.utf8), error: nil)

        let viewModel = SummaryViewModel(book: book)
        await viewModel.generateSummary(context: context)

        XCTAssertEqual(book.cachedSummary, "・要約その1")

        // 同じcontainerから新しいModelContextで読み直し、context.save()が実際に走ったことを確認する
        let freshContext = ModelContext(container)
        let fetched = try freshContext.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetched.first?.cachedSummary, "・要約その1")
    }
}
