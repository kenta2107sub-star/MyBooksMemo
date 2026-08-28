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
        let endpoint = request.url?.absoluteString ?? "unknown"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            log(endpoint: endpoint, statusCode: nil, errorCode: urlError.code.rawValue)
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost:
                throw APIError.network
            case .timedOut:
                throw APIError.timeout
            default:
                throw APIError.serverError
            }
        } catch {
            log(endpoint: endpoint, statusCode: nil, errorCode: nil)
            throw APIError.serverError
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            log(endpoint: endpoint, statusCode: nil, errorCode: nil)
            throw APIError.serverError
        }

        log(endpoint: endpoint, statusCode: httpResponse.statusCode, errorCode: nil)

        switch httpResponse.statusCode {
        case 200..<300:
            return (data, httpResponse)
        case 400:
            logWorkersErrorMessage(data)
            throw APIError.decodingError
        case 401:
            logWorkersErrorMessage(data)
            throw APIError.unauthorized
        case 404:
            throw APIError.decodingError
        case 429:
            logWorkersErrorMessage(data)
            throw APIError.rateLimited
        default:
            logWorkersErrorMessage(data)
            throw APIError.serverError
        }
    }

    /// FR-06共通ルールNo.5：ステータスコード・エンドポイント・タイムスタンプのみ出力する。
    /// メモ本文・対話内容等の個人情報はこの関数の引数として渡せない設計になっている
    /// （そもそもリクエストボディを引数に取らない）。
    private static func log(endpoint: String, statusCode: Int?, errorCode: Int?) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        if let statusCode {
            print("[APIClient] \(timestamp) \(endpoint) -> HTTP \(statusCode)")
        } else {
            print("[APIClient] \(timestamp) \(endpoint) -> transport error (code: \(errorCode.map(String.init) ?? "unknown"))")
        }
    }

    /// detailed_design.md 2-2・4-1：Cloudflare Workersのエラーレスポンス（`{error, message}`）の
    /// `message`はXcodeコンソールログにのみ出力してよい（画面表示には使わない）。
    /// NDL API等、この形式でないレスポンスはデコードに失敗するため何も出力しない（ベストエフォート）。
    private static func logWorkersErrorMessage(_ data: Data) {
        guard let response = try? JSONDecoder().decode(WorkersErrorResponse.self, from: data) else { return }
        print("[APIClient] Workers error detail: \(response.error) - \(response.message ?? "(no message)")")
    }
}
