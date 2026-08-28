import Foundation
import SwiftData

/// requirements.md FR-05異常系（basic_design.md Section 7 ERR-12〜14）に対応するエラー状態。
/// detailed_design.md 3-2：現行モックにはこの状態を表現するプロパティが存在しないため新規追加する。
enum SummaryFailureReason: Equatable {
    case apiFailure   // ERR-12
    case offline      // ERR-13
    case rateLimited  // ERR-14

    var message: String {
        switch self {
        case .apiFailure: return "要約の生成に失敗しました"
        case .offline: return "インターネットに接続されていないため要約を作成できません"
        case .rateLimited: return "本日の要約生成の利用上限に達しました"
        }
    }

    /// ERR-14（無料枠超過）のみ「再試行」ボタンを表示しない（時間経過でしか解消しないため）
    var showsRetryButton: Bool { self != .rateLimited }
}

// SCR-08 要約タブのViewModel。
// FR-05：「要約を作成する」ボタン押下時のみCloudflare Workers経由でGemini APIを呼び出す。
// @MainActor：非同期呼び出し後の状態更新（isGenerating・failureReason・book.cachedSummary等）を
// 安全にUIスレッドで行うため、クラス全体をMainActorに隔離する。
@Observable
@MainActor
final class SummaryViewModel {
    let book: Book
    var isGenerating = false
    var failureReason: SummaryFailureReason?

    /// 唯一の呼び出し元`BookDetailView.init(book:)`は`@MainActor`のViewのため、この初期化子を
    /// `nonisolated`にする必要はない。
    init(book: Book) {
        self.book = book
    }

    /// cachedSummaryの有無でボタンラベルを切り替える
    var buttonLabel: String {
        book.cachedSummary == nil ? "要約を作成する" : "要約を再作成する"
    }

    /// メモが1件もない場合はボタンを非活性にする
    var canGenerate: Bool {
        !book.memoEntries.isEmpty
    }

    var generatedAtText: String? {
        guard let generatedAt = book.cachedSummaryGeneratedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return "最終生成：\(formatter.string(from: generatedAt))"
    }

    /// - Parameter context: 成功時に`book.cachedSummary`／`cachedSummaryGeneratedAt`を明示的に
    ///   永続化するためのModelContext。他の書き込みパス（MemoEditorViewModel.save()・
    ///   BookDetailViewModel.triggerAdviceGeneration(for:context:)等）と同様、SwiftDataの
    ///   自動保存（autosave）任せにせず、Gemini API呼び出しに成功した時点で明示的にcontext.save()する
    ///   （自動保存のタイミング次第では、アプリ強制終了時に生成済みの要約が失われるおそれがあるため）。
    func generateSummary(context: ModelContext) async {
        guard canGenerate, !isGenerating else { return }
        failureReason = nil
        isGenerating = true
        defer { isGenerating = false }

        guard NetworkReachability.isConnected else {
            failureReason = .offline
            return
        }

        do {
            let response = try await CloudflareWorkersClient.shared.summarize(
                bookTitle: book.title,
                memos: book.memoEntries.map { (date: $0.date, content: $0.joinedContentForAI) },
                conversationLogs: book.conversationLogs.map { (date: $0.date, turns: $0.turns) }
            )
            book.cachedSummary = response.summary
            book.cachedSummaryGeneratedAt = .now
            try? context.save()
        } catch let error as APIError {
            failureReason = error.summaryFailureReason
        } catch {
            failureReason = .apiFailure
        }
    }
}
