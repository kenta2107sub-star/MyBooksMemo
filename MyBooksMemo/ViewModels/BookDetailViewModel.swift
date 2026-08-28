import Foundation
import SwiftData

/// SCR-05 本詳細画面のタブ（メモ一覧／要約）
enum DetailTab: String, CaseIterable, Identifiable {
    case memos = "メモ一覧"
    case summary = "要約"
    var id: String { rawValue }
}

/// FR-09の生成状態（UI層のみで保持。モデルの永続プロパティではない。detailed_design.md 1-4・3-2）
enum AdviceGenerationState: Equatable {
    case idle
    case generating
    case failed(AdviceFailureReason)
}

/// 「今日のアドバイス」付箋（常時表示）に表示する内容を一意に決める統合状態
enum AdviceDisplayState: Equatable {
    case notTriggered
    case generating
    case success(String)
    case failed(AdviceFailureReason)
}

/// requirements.md FR-09異常系・basic_design.md Section 7（ERR-15〜17）に対応
enum AdviceFailureReason: CaseIterable, Equatable {
    case apiFailure
    case offline
    case rateLimited

    var message: String {
        switch self {
        case .apiFailure: return "アドバイスの生成に失敗しました"
        case .offline: return "インターネットに接続されていないためアドバイスを生成できませんでした"
        case .rateLimited: return "本日のアドバイス生成の利用上限に達しました"
        }
    }

    /// ERR-17（無料枠超過）のみ「再試行」ボタンを表示しない（時間経過でしか解消しないため）
    var showsRetryButton: Bool { self != .rateLimited }
}

// SCR-05 本詳細画面（メモ一覧タブ）のViewModel。
// @MainActor：FR-09の非同期アドバイス生成後の状態更新を安全にUIスレッドで行うため、
// クラス全体をMainActorに隔離する。
@Observable
@MainActor
final class BookDetailViewModel {
    let book: Book
    var selectedTab: DetailTab = .memos

    var memoPendingDeletion: MemoEntry?
    var isShowingDeleteConfirmation = false

    /// FR-09：MemoEntry.idをキーにした一時的な生成状態（detailed_design.md 1-4・3-2）
    private var adviceStates: [UUID: AdviceGenerationState] = [:]

    /// 唯一の呼び出し元`BookDetailView.init(book:)`は`@MainActor`のViewのため、この初期化子を
    /// `nonisolated`にする必要はない。
    init(book: Book) {
        self.book = book
    }

    /// 日付降順で並べたメモ一覧
    var sortedMemos: [MemoEntry] {
        book.memoEntries.sorted { $0.date > $1.date }
    }

    var hasMemos: Bool { !book.memoEntries.isEmpty }

    /// FR-08：同一book・同一dateのConversationLogを探す。存在すればメモカードの振り返りアイコンを活性にする
    func conversationLog(for memo: MemoEntry) -> ConversationLog? {
        book.conversationLogs.first { Calendar.current.isDate($0.date, inSameDayAs: memo.date) }
    }

    /// DLG-02：メモカードの左スワイプ→「削除」タップ時に呼ばれる
    func requestDelete(_ memo: MemoEntry) {
        memoPendingDeletion = memo
        isShowingDeleteConfirmation = true
    }

    /// 「削除する」タップ → 対象メモを削除する。
    /// detailed_design.md 1-3：同一book・同一dateのConversationLogも連動削除する（cachedSummaryは保持）
    func confirmDelete(context: ModelContext) {
        guard let memo = memoPendingDeletion else { return }
        let targetDate = memo.date

        book.conversationLogs
            .filter { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }
            .forEach { context.delete($0) }

        context.delete(memo)
        try? context.save()

        memoPendingDeletion = nil
        isShowingDeleteConfirmation = false
    }

    /// 「キャンセル」タップ → 何もせずメモ一覧に留まる
    func cancelDelete() {
        memoPendingDeletion = nil
        isShowingDeleteConfirmation = false
    }

    // MARK: - FR-09：今日のアドバイス（detailed_design.md 3-2）

    func adviceDisplayState(for memo: MemoEntry) -> AdviceDisplayState {
        if let advice = memo.dailyAdvice { return .success(advice) }
        switch adviceStates[memo.id] ?? .idle {
        case .idle: return .notTriggered
        case .generating: return .generating
        case .failed(let reason): return .failed(reason)
        }
    }

    /// メモ内容（＋対話ログがあれば対話内容）をもとに「今日のアドバイス」をバックグラウンドで生成する。
    /// 呼び出し元（MemoEditorView：対話スキップ時、AIChatViewModel：対話終了時）の画面遷移はブロックしない。
    func triggerAdviceGeneration(for memo: MemoEntry, context: ModelContext) {
        guard adviceStates[memo.id] != .generating else { return }
        adviceStates[memo.id] = .generating

        let bookTitle = memo.book?.title ?? book.title
        let memoContent = memo.joinedContentForAI
        let conversationTurns = conversationLog(for: memo)?.turns ?? []

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard NetworkReachability.isConnected else {
                self.adviceStates[memo.id] = .failed(.offline)
                return
            }
            do {
                let response = try await CloudflareWorkersClient.shared.generateAdvice(
                    bookTitle: bookTitle,
                    memoContent: memoContent,
                    conversationTurns: conversationTurns
                )
                memo.dailyAdvice = response.advice
                try? context.save()
                self.adviceStates[memo.id] = .idle
            } catch let error as APIError {
                self.adviceStates[memo.id] = .failed(error.adviceFailureReason)
            } catch {
                self.adviceStates[memo.id] = .failed(.apiFailure)
            }
        }
    }
}
