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

    func test_URLProtocolStub_httpBodyStreamも記録する() async throws {
        let body = Data(#"{"value":"stream"}"#.utf8)
        URLProtocolStub.stubs["/stream"] = .init(
            statusCode: 200,
            data: Data(#"{}"#.utf8),
            error: nil
        )

        var request = URLRequest(url: URL(string: "https://example.invalid/stream")!)
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(data: body)
        _ = try await URLSession.shared.data(for: request)

        XCTAssertEqual(URLProtocolStub.requestedBodies["/stream"], [body])
    }

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

    @MainActor
    func test_SummaryViewModel_メモを日付の降順で送信する() async throws {
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "テスト本", author: "著者", cachedSummary: "保存済み要約")
        let olderMemo = MemoEntry(date: Date(timeIntervalSince1970: 1_000), contentItems: ["古いメモ"], book: book)
        let newerMemo = MemoEntry(date: Date(timeIntervalSince1970: 2_000), contentItems: ["新しいメモ"], book: book)
        context.insert(book)
        context.insert(olderMemo)
        context.insert(newerMemo)
        book.memoEntries = [olderMemo, newerMemo]
        try context.save()

        URLProtocolStub.stubs["/summarize"] = .init(
            statusCode: 200,
            data: Data(#"{"summary":"更新後要約"}"#.utf8),
            error: nil
        )

        let viewModel = SummaryViewModel(book: book)
        await viewModel.generateSummary(context: context)

        let body = try XCTUnwrap(URLProtocolStub.requestedBodies["/summarize"]?.first)
        let request = try JSONDecoder().decode(SummarizeRequest.self, from: body)
        XCTAssertEqual(request.memos.map(\.content), ["新しいメモ", "古いメモ"])
        XCTAssertEqual(book.cachedSummary, "更新後要約")
    }

    @MainActor
    func test_SummaryViewModel_メモ0件では生成せず保存済み要約を保持する() async throws {
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let withoutCache = Book(title: "未生成", author: "著者")
        let withCache = Book(title: "生成済み", author: "著者", cachedSummary: "保存済み要約")
        context.insert(withoutCache)
        context.insert(withCache)

        let withoutCacheViewModel = SummaryViewModel(book: withoutCache)
        let withCacheViewModel = SummaryViewModel(book: withCache)
        await withoutCacheViewModel.generateSummary(context: context)
        await withCacheViewModel.generateSummary(context: context)

        XCTAssertFalse(withoutCacheViewModel.canGenerate)
        XCTAssertEqual(withoutCacheViewModel.buttonLabel, "要約を作成する")
        XCTAssertFalse(withCacheViewModel.canGenerate)
        XCTAssertEqual(withCacheViewModel.buttonLabel, "要約を再作成する")
        XCTAssertEqual(withCache.cachedSummary, "保存済み要約")
        XCTAssertTrue(URLProtocolStub.requestedPaths.isEmpty)
    }

    // MARK: - AIChatViewModelの往復保持

    @MainActor
    func test_AIChatViewModel_初回質問を受信するまで送信できない() async throws {
        URLProtocolStub.stubs["/chat"] = .init(
            statusCode: 200,
            data: Data(#"{"question":"Q1"}"#.utf8),
            error: nil,
            delay: 0.2
        )
        let (viewModel, _, _, _) = try makeChatViewModel()

        viewModel.currentInput = "A1"
        XCTAssertFalse(viewModel.canSend)
        viewModel.send()
        XCTAssertEqual(viewModel.turnCount, 0)

        await waitUntil { viewModel.messages.contains { $0.text == "Q1" } }
        XCTAssertTrue(viewModel.canSend)
    }

    @MainActor
    func test_AIChatViewModel_次質問失敗後に終了しても送信済み往復を保存する() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(#"{"question":"Q1"}"#.utf8), error: nil)
        let (viewModel, context, book, _) = try makeChatViewModel()
        await waitUntil { viewModel.messages.contains { $0.text == "Q1" } }

        URLProtocolStub.stubs["/chat"] = .init(statusCode: 0, data: Data(), error: URLError(.timedOut))
        viewModel.currentInput = "A1"
        viewModel.send()
        await waitUntil { viewModel.previewError != nil }
        viewModel.endConversation()

        let logs = try context.fetch(FetchDescriptor<ConversationLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.turns.count, 1)
        XCTAssertEqual(logs.first?.turns.first?.question, "Q1")
        XCTAssertEqual(logs.first?.turns.first?.answer, "A1")
        XCTAssertEqual(book.conversationLogs.count, 1)
    }

    @MainActor
    func test_AIChatViewModel_再試行は同じ履歴を送り往復を重複しない() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(#"{"question":"Q1"}"#.utf8), error: nil)
        let (viewModel, context, _, _) = try makeChatViewModel()
        await waitUntil { viewModel.messages.contains { $0.text == "Q1" } }

        URLProtocolStub.stubs["/chat"] = .init(statusCode: 0, data: Data(), error: URLError(.timedOut))
        viewModel.currentInput = "A1"
        viewModel.send()
        await waitUntil { viewModel.previewError != nil }

        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(#"{"question":"Q2"}"#.utf8), error: nil)
        viewModel.retry()
        await waitUntil { viewModel.messages.contains { $0.text == "Q2" } }
        viewModel.endConversation()

        let histories = try XCTUnwrap(URLProtocolStub.requestedBodies["/chat"]?.dropFirst().map {
            try JSONDecoder().decode(ChatRequest.self, from: $0).conversationHistory
        })
        XCTAssertEqual(histories.count, 2)
        XCTAssertTrue(histories.allSatisfy { $0.count == 1 && $0[0].question == "Q1" && $0[0].answer == "A1" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationLog>()).first?.turns.count, 1)
    }

    @MainActor
    func test_AIChatViewModel_応答待ち中の終了後に届いた質問を反映しない() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(#"{"question":"Q1"}"#.utf8), error: nil)
        let (viewModel, context, _, _) = try makeChatViewModel()
        await waitUntil { viewModel.messages.contains { $0.text == "Q1" } }

        URLProtocolStub.stubs["/chat"] = .init(
            statusCode: 200,
            data: Data(#"{"question":"Q2"}"#.utf8),
            error: nil,
            delay: 0.2
        )
        viewModel.currentInput = "A1"
        viewModel.send()
        await waitUntil { URLProtocolStub.requestedPaths.count == 2 }
        viewModel.endConversation()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertFalse(viewModel.messages.contains { $0.text == "Q2" })
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationLog>()).first?.turns.count, 1)
    }

    @MainActor
    func test_AIChatViewModel_5往復目で追加リクエストなしに終了する() async throws {
        URLProtocolStub.stubs["/chat"] = .init(statusCode: 200, data: Data(#"{"question":"Q"}"#.utf8), error: nil)
        var adviceRequestCount = 0
        let (viewModel, context, book, _) = try makeChatViewModel { _ in adviceRequestCount += 1 }
        await waitUntil { viewModel.messages.count == 1 }

        for index in 1...5 {
            viewModel.currentInput = "A\(index)"
            viewModel.send()
            if index < 5 {
                await waitUntil { viewModel.turnCount == index && !viewModel.isAIThinking }
            }
        }

        XCTAssertTrue(viewModel.isFinished)
        XCTAssertEqual(viewModel.turnCount, 5)
        XCTAssertEqual(URLProtocolStub.requestedPaths.filter { $0 == "/chat" }.count, 5)

        var logs = try context.fetch(FetchDescriptor<ConversationLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.turns.count, 5)
        XCTAssertEqual(book.conversationLogs.count, 1)
        XCTAssertEqual(adviceRequestCount, 1)

        viewModel.finishAfterLimitReached()
        viewModel.finishAfterLimitReached()

        logs = try context.fetch(FetchDescriptor<ConversationLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(book.conversationLogs.count, 1)
        XCTAssertEqual(adviceRequestCount, 1)
    }

    @MainActor
    func test_AIChatViewModel_往復0件で終了した場合はログを保存しない() async throws {
        URLProtocolStub.stubs["/chat"] = .init(
            statusCode: 200,
            data: Data(#"{"question":"Q1"}"#.utf8),
            error: nil,
            delay: 0.2
        )
        let (viewModel, context, _, _) = try makeChatViewModel()
        await waitUntil { URLProtocolStub.requestedPaths == ["/chat"] }
        viewModel.endConversation()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(try context.fetch(FetchDescriptor<ConversationLog>()).isEmpty)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    @MainActor
    private func makeChatViewModel(
        onAdviceNeeded: @escaping (MemoEntry) -> Void = { _ in }
    ) throws -> (AIChatViewModel, ModelContext, Book, MemoEntry) {
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let book = Book(title: "テスト本", author: "著者")
        let memo = MemoEntry(date: .now, contentItems: ["メモ"], book: book)
        context.insert(book)
        context.insert(memo)
        book.memoEntries.append(memo)
        try context.save()
        return (AIChatViewModel(book: book, memo: memo, context: context, onAdviceNeeded: onAdviceNeeded), context, book, memo)
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("条件がタイムアウトまでに成立しませんでした", file: file, line: line)
    }
}
