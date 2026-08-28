import Foundation

// detailed_design.md 4-1・2-3：Cloudflare Workers `/chat`・`/summarize`・`/advice`呼び出し。
// architecture.md 7.1：`Config.swift`からCLOUDFLARE_WORKERS_URL・WORKERS_SHARED_SECRETを読み取り、
// リクエスト生成とレスポンスDecodeを担う。ViewModelはこのクライアントのメソッドを呼ぶだけでよい。

// MARK: - リクエスト/レスポンス型（detailed_design.md 4-1）

struct ChatRequest: Codable {
    let bookTitle: String
    let memoContent: String
    let conversationHistory: [ConversationTurn]
}
struct ChatResponse: Codable {
    let question: String
}

struct MemoSummaryInput: Codable {
    let date: String     // "yyyy-MM-dd"形式
    let content: String
}
struct ConversationLogSummaryInput: Codable {
    let date: String
    let turns: [ConversationTurn]
}
struct SummarizeRequest: Codable {
    let bookTitle: String
    let memos: [MemoSummaryInput]
    let conversationLogs: [ConversationLogSummaryInput]
}
struct SummarizeResponse: Codable {
    let summary: String
}

struct AdviceRequest: Codable {
    let bookTitle: String
    let memoContent: String
    let conversationTurns: [ConversationTurn]
}
struct AdviceResponse: Codable {
    let advice: String
}

/// Workers側のエラーレスポンス（detailed_design.md 2-2）。iOS側はHTTPステータスコードで判定するため
/// この型自体をUI表示に使うことはないが、Xcodeコンソールログ出力（FR-06 No.5）には使う
struct WorkersErrorResponse: Codable {
    let error: String
    let message: String?
}

// MARK: - クライアント本体

final class CloudflareWorkersClient {
    static let shared = CloudflareWorkersClient()

    private init() {}

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    /// FR-04：往復のたびに呼ばれる。次のAIの質問テキストを1件取得する
    func chat(bookTitle: String, memoContent: String, conversationHistory: [ConversationTurn]) async throws -> ChatResponse {
        let body = ChatRequest(bookTitle: bookTitle, memoContent: memoContent, conversationHistory: conversationHistory)
        return try await post(path: "/chat", body: body)
    }

    /// FR-05：「要約を作成する」ボタンタップ時のみ呼ばれる
    func summarize(bookTitle: String, memos: [(date: Date, content: String)], conversationLogs: [(date: Date, turns: [ConversationTurn])]) async throws -> SummarizeResponse {
        let memoInputs = memos.map { MemoSummaryInput(date: Self.dateFormatter.string(from: $0.date), content: $0.content) }
        let logInputs = conversationLogs.map { ConversationLogSummaryInput(date: Self.dateFormatter.string(from: $0.date), turns: $0.turns) }
        let body = SummarizeRequest(bookTitle: bookTitle, memos: memoInputs, conversationLogs: logInputs)
        return try await post(path: "/summarize", body: body)
    }

    /// FR-09：メモ保存後（対話スキップ時）または対話終了時にバックグラウンドで呼ばれる
    func generateAdvice(bookTitle: String, memoContent: String, conversationTurns: [ConversationTurn]) async throws -> AdviceResponse {
        let body = AdviceRequest(bookTitle: bookTitle, memoContent: memoContent, conversationTurns: conversationTurns)
        return try await post(path: "/advice", body: body)
    }

    // MARK: - 共通POST処理

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: Config.cloudflareWorkersURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.workersSharedSecret, forHTTPHeaderField: "X-Shared-Secret")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decodingError
        }

        // FR-06共通ルールNo.2：Gemini API（Cloudflare Workers経由）は15秒タイムアウト
        let (data, _) = try await APIClient.send(request, timeout: 15)

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decodingError
        }
    }
}
