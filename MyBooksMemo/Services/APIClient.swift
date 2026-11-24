import Foundation

// architecture.md 7.1：NDLSearchService・CloudflareWorkersClientの両方が依存する共通層。
// タイムアウト値は呼び出し元が指定し、ここでは汎用的なsend(request:timeout:)のみ提供する。
// FR-06共通ルール（自動リトライなし・ログ出力）をここに集約する。
enum APIClient {
    /// リクエストを送信し、成功時（HTTP 2xx）は(Data, HTTPURLResponse)を返す。
    /// 失敗時はHTTPステータスコード／URLErrorをAPIErrorに変換してthrowする。
    /// FR-06共通ルールNo.3：ここにリトライ機構は実装しない。「再試行」ボタンはView側のユーザー操作から
    /// 同じメソッドを再度呼ぶだけにする。
    static func send(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost:
                throw APIError.network
            case .timedOut:
                throw APIError.timeout
            default:
                throw APIError.serverError
            }
        } catch {
            throw APIError.serverError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.serverError
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return (data, httpResponse)
        case 400:
            logHTTPFailure(path: request.url?.path ?? "unknown", statusCode: httpResponse.statusCode)
            throw APIError.decodingError
        case 401:
            logHTTPFailure(path: request.url?.path ?? "unknown", statusCode: httpResponse.statusCode)
            throw APIError.unauthorized
        case 404:
            logHTTPFailure(path: request.url?.path ?? "unknown", statusCode: httpResponse.statusCode)
            throw APIError.decodingError
        case 429:
            logHTTPFailure(path: request.url?.path ?? "unknown", statusCode: httpResponse.statusCode)
            throw APIError.rateLimited
        default:
            logHTTPFailure(path: request.url?.path ?? "unknown", statusCode: httpResponse.statusCode)
            throw APIError.serverError
        }
    }

    /// FR-06共通ルールNo.5：HTTP応答を受信した失敗時だけを出力する。
    private static func logHTTPFailure(path: String, statusCode: Int) {
        print(failureLogMessage(path: path, statusCode: statusCode))
    }

    /// テスト可能なログ整形処理。URL全体・ヘッダー・ボディ・
    /// Workersエラー詳細を受け取らないことで、秘密情報の混入を構造的に防ぐ。
    static func failureLogMessage(
        path: String,
        statusCode: Int,
        timestamp: Date = .now
    ) -> String {
        let timestampText = ISO8601DateFormatter().string(from: timestamp)
        return "[APIClient] \(timestampText) \(path) -> HTTP \(statusCode)"
    }
}
