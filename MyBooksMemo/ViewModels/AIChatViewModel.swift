import Foundation
import SwiftData

/// SCR-07のチャット1発言分。
struct ChatMessage: Identifiable, Equatable {
    enum Sender { case ai, user }
    let id = UUID()
    let sender: Sender
    let text: String
}

/// requirements.md FR-04異常系（basic_design.md Section 7 ERR-09〜11）に対応するエラー状態。
enum ChatPreviewError: String, CaseIterable, Identifiable {
    case apiFailure = "通信失敗"
    case offline = "オフライン"
    case rateLimited = "利用上限"

    var id: String { rawValue }

    var message: String {
        switch self {
        case .apiFailure: return "AIとの通信に失敗しました。もう一度お試しください"
        case .offline: return "インターネットに接続されていません"
        case .rateLimited: return "本日のAI対話の利用上限に達しました。しばらく時間をおいてから再度お試しください"
        }
    }
}

// SCR-07は通常モード（FR-04）と読み取り専用モード（FR-08）を同一Viewから出し分ける。
// basic_design.md「読み取り専用モードでは新しい画面IDは作らず、モード切り替えパラメータを追加する」に対応。
enum AIChatMode: Equatable {
    /// FR-04：メモ保存直後にGemini APIとの対話を行う
    case interactive
    /// FR-08：保存済みConversationLogを見返すだけのモード。API通信は一切発生しない
    case readOnly
}

// @MainActor：非同期のGemini API呼び出し後の状態更新を安全にUIスレッドで行うため、
// クラス全体をMainActorに隔離する。
@Observable
@MainActor
final class AIChatViewModel {
    let mode: AIChatMode

    // 通常モード（.interactive）でのみ使用。読み取り専用モードでは保存対象がないためnil
    private let book: Book?
    private let memo: MemoEntry?
    private let modelContext: ModelContext?
    /// FR-09：対話終了時にアドバイス生成をトリガーするためのコールバック
    /// （detailed_design.md 1-4・3-2：状態はBookDetailViewModelが保持するため、
    /// 直接メソッドを呼ばずクロージャ経由で委譲する）
    private let onAdviceNeeded: ((MemoEntry) -> Void)?

    let maxTurns = 5

    var messages: [ChatMessage] = []
    var currentInput: String = ""
    var turnCount = 0
    var isFinished = false
    var isAIThinking = false
    var previewError: ChatPreviewError?

    private var lastQuestionText = ""
    private var pendingTurns: [ConversationTurn] = []
    private var pendingRetryTurn: ConversationTurn?
    private var hasSaved = false
    private var hasTriggeredAdvice = false

    /// 唯一の呼び出し元`AIChatView.init(book:memo:onAdviceNeeded:)`は`@MainActor`のViewのため、
    /// この初期化子を`nonisolated`にする必要はない。
    /// 通常モード（FR-04）：メモ保存後にSCR-06から遷移してくる対話フロー
    init(book: Book, memo: MemoEntry, context: ModelContext, onAdviceNeeded: @escaping (MemoEntry) -> Void) {
        self.mode = .interactive
        self.book = book
        self.memo = memo
        self.modelContext = context
        self.onAdviceNeeded = onAdviceNeeded
        Task { [weak self] in await self?.askFirstQuestion() }
    }

    /// 読み取り専用モード（FR-08）：保存済みConversationLogをそのまま表示するだけで、質問生成・保存は行わない。
    /// 唯一の呼び出し元`AIChatView.init(conversationLog:)`は`@MainActor`のViewから呼ばれるため、
    /// この初期化子は`nonisolated`にしない（`isFinished`・`messages`は宣言時のデフォルト値を
    /// 上書きする＝再代入とみなされ、nonisolatedからは行えないため）。
    init(conversationLog: ConversationLog) {
        self.mode = .readOnly
        self.book = nil
        self.memo = nil
        self.modelContext = nil
        self.onAdviceNeeded = nil
        self.isFinished = true
        self.messages = conversationLog.turns.flatMap { turn in
            [ChatMessage(sender: .ai, text: turn.question), ChatMessage(sender: .user, text: turn.answer)]
        }
    }

    var progressText: String {
        "往復 \(min(turnCount, maxTurns)) / \(maxTurns)（最大\(maxTurns)往復で自動終了します）"
    }

    var hasAtLeastOneTurn: Bool { !pendingTurns.isEmpty }

    var canSend: Bool {
        mode == .interactive && !isFinished && !isAIThinking && previewError == nil
            && !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Gemini API呼び出し（FR-04）

    /// 初回の質問取得（`/chat`、conversationHistory: []）
    private func askFirstQuestion() async {
        guard let memo else { return }
        guard NetworkReachability.isConnected else {
            await MainActor.run { self.previewError = .offline }
            return
        }
        await MainActor.run { self.isAIThinking = true }
        do {
            let response = try await CloudflareWorkersClient.shared.chat(
                bookTitle: book?.title ?? "",
                memoContent: memo.joinedContentForAI,
                conversationHistory: []
            )
            await MainActor.run {
                self.isAIThinking = false
                self.lastQuestionText = response.question
                self.messages.append(ChatMessage(sender: .ai, text: response.question))
            }
        } catch let error as APIError {
            await MainActor.run {
                self.isAIThinking = false
                self.previewError = error.chatFailureReason
            }
        } catch {
            await MainActor.run {
                self.isAIThinking = false
                self.previewError = .apiFailure
            }
        }
    }

    /// テキストを入力して「送信」。5往復目の回答の場合はGemini APIを呼び出さずローカルで終了する
    /// （requirements.md FR-04 Step5：「それ以上AIへのリクエストは行わずアプリ側で会話を終了する」）
    func send() {
        guard canSend, let memo else { return }
        let answer = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(ChatMessage(sender: .user, text: answer))
        currentInput = ""

        let completedTurn = ConversationTurn(question: lastQuestionText, answer: answer)

        if turnCount + 1 >= maxTurns {
            pendingTurns.append(completedTurn)
            turnCount += 1
            isFinished = true
            messages.append(ChatMessage(sender: .ai, text: "言語化についてのAI対話は今回はここまでです。お疲れさまでした"))
            return
        }

        Task { [weak self] in await self?.requestNextQuestion(completedTurn: completedTurn, memo: memo) }
    }

    private func requestNextQuestion(completedTurn: ConversationTurn, memo: MemoEntry) async {
        await MainActor.run { self.isAIThinking = true }

        guard NetworkReachability.isConnected else {
            await MainActor.run {
                self.isAIThinking = false
                self.previewError = .offline
                self.pendingRetryTurn = completedTurn
            }
            return
        }

        let historyForRequest = pendingTurns + [completedTurn]

        do {
            let response = try await CloudflareWorkersClient.shared.chat(
                bookTitle: book?.title ?? "",
                memoContent: memo.joinedContentForAI,
                conversationHistory: historyForRequest
            )
            await MainActor.run {
                self.isAIThinking = false
                self.pendingTurns.append(completedTurn)
                self.turnCount += 1
                self.lastQuestionText = response.question
                self.messages.append(ChatMessage(sender: .ai, text: response.question))
            }
        } catch let error as APIError {
            await MainActor.run {
                self.isAIThinking = false
                self.previewError = error.chatFailureReason
                self.pendingRetryTurn = completedTurn
            }
        } catch {
            await MainActor.run {
                self.isAIThinking = false
                self.previewError = .apiFailure
                self.pendingRetryTurn = completedTurn
            }
        }
    }

    /// エラー表示中の「再試行」ボタン（FR-06共通ルールNo.3：ユーザー操作を起点にのみ再送する）
    func retry() {
        guard mode == .interactive else { return }
        previewError = nil
        if let turn = pendingRetryTurn, let memo {
            pendingRetryTurn = nil
            Task { [weak self] in await self?.requestNextQuestion(completedTurn: turn, memo: memo) }
        } else {
            Task { [weak self] in await self?.askFirstQuestion() }
        }
    }

    /// 右上「終了する」（いつでも押せる。確認ダイアログなし）。読み取り専用モードでは使わない
    func endConversation() {
        guard mode == .interactive else { return }
        isFinished = true
        saveIfNeeded()
        triggerAdviceIfNeeded()
    }

    /// 5往復到達→終了メッセージ表示後「本詳細画面に戻る」。読み取り専用モードでは使わない
    func finishAfterLimitReached() {
        guard mode == .interactive else { return }
        saveIfNeeded()
        triggerAdviceIfNeeded()
    }

    /// 対話が1ターンも成立していない場合は保存しない（requirements.md FR-04補足）
    @discardableResult
    private func saveIfNeeded() -> ConversationLog? {
        guard !hasSaved, let book, let memo, let modelContext else { return nil }
        hasSaved = true
        guard hasAtLeastOneTurn else { return nil }
        let log = ConversationLog(date: memo.date, turns: pendingTurns)
        modelContext.insert(log)
        log.book = book
        book.conversationLogs.append(log)
        try? modelContext.save()
        return log
    }

    /// FR-09 トリガー経路B：対話終了時点（往復上限到達／「終了する」タップ）で、メモ内容＋対話ログ
    /// （1ターンも成立せずConversationLogが保存されなかった場合はメモ内容のみ）でアドバイス生成を
    /// バックグラウンドでトリガーする。画面遷移は生成完了を待たずに行う
    private func triggerAdviceIfNeeded() {
        guard !hasTriggeredAdvice, let memo else { return }
        hasTriggeredAdvice = true
        onAdviceNeeded?(memo)
    }
}
