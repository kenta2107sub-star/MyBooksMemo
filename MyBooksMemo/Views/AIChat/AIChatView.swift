import SwiftUI
import SwiftData
import UIKit

// SCR-07：AI対話画面（チャット形式）。
// 対応FR：FR-04（通常モード）, FR-08（読み取り専用モード）
// 新しい画面IDは作らず、AIChatViewModel.modeによって同一Viewから通常／読み取り専用を出し分ける。
// @MainActor：`AIChatViewModel`が`@MainActor`のため、`body`以外の算出プロパティからも
// 安全に参照できるよう、View全体をMainActorに揃える。
@MainActor
struct AIChatView: View {
    @State private var viewModel: AIChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// 通常モード（FR-04）：SCR-06のメモ保存後にAIと対話する
    init(book: Book, memo: MemoEntry, onAdviceNeeded: @escaping (MemoEntry) -> Void = { _ in }) {
        let context = book.modelContext ?? memo.modelContext
        guard let context else {
            fatalError("AIChatView(book:memo:) にはSwiftDataのModelContextに登録済みのBook/MemoEntryを渡す必要があります")
        }
        _viewModel = State(initialValue: AIChatViewModel(book: book, memo: memo, context: context, onAdviceNeeded: onAdviceNeeded))
    }

    /// 読み取り専用モード（FR-08）：SCR-05の振り返りアイコンから保存済み対話ログを見返す
    init(conversationLog: ConversationLog) {
        _viewModel = State(initialValue: AIChatViewModel(conversationLog: conversationLog))
    }

    private var isReadOnly: Bool { viewModel.mode == .readOnly }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            VStack(spacing: 0) {
                if !isReadOnly {
                    progressBar
                }

                chatScroll

                if !isReadOnly {
                    if let previewError = viewModel.previewError {
                        errorBanner(previewError)
                    } else if viewModel.isFinished {
                        finishedFooter
                    } else {
                        inputBar
                    }
                }
            }
            .background(BookTheme.background.ignoresSafeArea())
            .navigationTitle(isReadOnly ? "AIとの対話（振り返り）" : "AIとの対話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isReadOnly {
                        // FR-08：読み取り専用モードは「閉じる」のみ。対話ログの変更・削除は発生しない
                        Button("閉じる") { dismiss() }
                            .font(BookTheme.button(.body))
                            .foregroundStyle(BookTheme.primary)
                    } else {
                        Button("終了する") {
                            viewModel.endConversation()
                            dismiss()
                        }
                        .font(BookTheme.button(.body))
                        .foregroundStyle(BookTheme.primary)
                    }
                }
            }
        }
        // basic_design.md 画面一覧：通常モードはdismiss制限あり、読み取り専用モードは制限なし
        .interactiveDismissDisabled(!isReadOnly)
    }

    // MARK: - 往復進捗表示

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.progressText)
                .font(BookTheme.button(.caption))
                .foregroundStyle(BookTheme.textSecondary)

            GeometryReader { geometry in
                let ratio = min(Double(viewModel.turnCount), Double(viewModel.maxTurns)) / Double(viewModel.maxTurns)
                ZStack(alignment: .leading) {
                    Capsule().fill(BookTheme.border)
                    // secondary（アンバー）はborderとの非テキストコントラストが3:1未満のため、
                    // 視認性を確保できるprimaryを使う（4.07:1）
                    Capsule()
                        .fill(BookTheme.primary)
                        .frame(width: geometry.size.width * ratio)
                        .animation(.reduceMotionAware(.easeInOut(duration: 0.3)), value: viewModel.turnCount)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, BookTheme.screenMargin)
        .padding(.top, BookTheme.spacingUnit)
        .padding(.bottom, BookTheme.spacingUnit)
    }

    // MARK: - チャット本体

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: BookTheme.spacingUnit * 1.5) {
                    ForEach(viewModel.messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                    if viewModel.isAIThinking {
                        TypingIndicatorBubble()
                            .id("typing-indicator")
                    }
                }
                .padding(.horizontal, BookTheme.screenMargin)
                .padding(.vertical, BookTheme.spacingUnit)
            }
            .onChange(of: viewModel.messages) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isAIThinking) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.reduceMotionAware(.easeOut(duration: 0.2))) {
            if viewModel.isAIThinking {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else {
                proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
            }
        }
    }

    // MARK: - 入力欄

    private var inputBar: some View {
        @Bindable var viewModel = viewModel
        return HStack(spacing: BookTheme.spacingUnit) {
            TextField("回答を入力…", text: $viewModel.currentInput, axis: .vertical)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textPrimary)
                .lineLimit(1...4)
                .padding(10)
                .background(BookTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: BookTheme.textFieldCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BookTheme.textFieldCornerRadius, style: .continuous)
                        .strokeBorder(isInputFocused ? BookTheme.primary : BookTheme.border, lineWidth: isInputFocused ? 2 : 1)
                )
                .focused($isInputFocused)
                .disabled(viewModel.isAIThinking)

            Button {
                viewModel.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(viewModel.canSend ? BookTheme.primary : BookTheme.textSecondary.opacity(0.5))
            .disabled(!viewModel.canSend)
            .accessibilityLabel("送信")
        }
        .padding(BookTheme.screenMargin)
        .background(BookTheme.cardBackground.opacity(0.6))
    }

    // MARK: - 5往復到達後のフッター

    private var finishedFooter: some View {
        Button("本詳細画面に戻る") {
            viewModel.finishAfterLimitReached()
            dismiss()
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(BookTheme.screenMargin)
    }

    // MARK: - エラー状態（ERR-09〜11）

    @ViewBuilder
    private func errorBanner(_ error: ChatPreviewError) -> some View {
        VStack(spacing: BookTheme.spacingUnit) {
            Text(error.message)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.error)
                .multilineTextAlignment(.center)

            switch error {
            case .apiFailure:
                Button("再試行") { viewModel.retry() }
                    .buttonStyle(SecondaryButtonStyle())
            case .offline:
                Button("本詳細画面に戻る") {
                    viewModel.endConversation()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
            case .rateLimited:
                Text("右上の「終了する」から退出できます")
                    .font(BookTheme.caption)
                    .foregroundStyle(BookTheme.textSecondary)
            }
        }
        .padding(BookTheme.screenMargin)
        .background(BookTheme.cardBackground)
    }

}

// MARK: - チャットバブル

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.sender == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: BookTheme.chatBubbleCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BookTheme.chatBubbleCornerRadius, style: .continuous)
                        .strokeBorder(message.sender == .ai ? BookTheme.primary.opacity(0.4) : Color.clear, lineWidth: 1)
                )

            if message.sender == .ai { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: Color {
        message.sender == .ai ? BookTheme.background : BookTheme.secondary
    }
}

/// AI応答待ち中のタイピングインジケーター。reduce motion時は静的な「…」表示にする。
private struct TypingIndicatorBubble: View {
    @State private var animate = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(BookTheme.primary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .offset(y: animate && !UIAccessibility.isReduceMotionEnabled ? -3 : 0)
                        .animation(
                            UIAccessibility.isReduceMotionEnabled ? nil :
                                .easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BookTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: BookTheme.chatBubbleCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BookTheme.chatBubbleCornerRadius, style: .continuous)
                    .strokeBorder(BookTheme.primary.opacity(0.4), lineWidth: 1)
            )
            .onAppear { animate = true }

            Spacer(minLength: 40)
        }
    }
}

#Preview("通常モード") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    container.mainContext.insert(book)
    try? container.mainContext.save()
    return AIChatView(book: book, memo: book.memoEntries[0])
        .modelContainer(container)
}

#Preview("読み取り専用モード（FR-08）") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    container.mainContext.insert(book)
    return AIChatView(conversationLog: book.conversationLogs[0])
        .modelContainer(container)
}
