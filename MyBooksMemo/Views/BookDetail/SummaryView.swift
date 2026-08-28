import SwiftUI
import SwiftData

// SCR-08：要約タブの中身（SCR-05内の「要約」タブとして配置）。
// FR-05：「要約を作成する」ボタン押下時のみCloudflare Workers経由でGemini APIを呼び出す。
// @MainActor：`SummaryViewModel`が`@MainActor`のため、`body`以外の算出プロパティからも
// 安全に参照できるよう、View全体をMainActorに揃える（SwiftUIは実行時常にMainActorで描画される）。
@MainActor
struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let viewModel: SummaryViewModel

    var body: some View {
        ScrollView {
            Group {
                if let summary = viewModel.book.cachedSummary {
                    generatedContent(summary: summary)
                } else if viewModel.canGenerate {
                    notYetGeneratedState
                } else {
                    noMemosState
                }
            }
            .padding(BookTheme.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BookTheme.background)
        .animation(.reduceMotionAware(.easeInOut(duration: 0.3)), value: viewModel.book.cachedSummary)
    }

    // MARK: - cachedSummaryが存在する場合（要約カード＝背景コンテナ。basic_design.md Section 4）

    private func generatedContent(summary: String) -> some View {
        VStack(alignment: .leading, spacing: BookTheme.spacingUnit * 2) {
            Text(summary)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)

            if let generatedAtText = viewModel.generatedAtText {
                // basic_design.md 5.4.6②：生成日時テキストをMemoCardViewと同じ付箋風バッジ
                // （背景ブックブラウン・角丸4pt・文字色白）にし、テープ留め装飾を適用する。
                // 2026-08-13再確定：MemoCardViewの日付バッジの配色変更に追随（5.2参照）
                Text(generatedAtText)
                    .font(BookTheme.caption)
                    .foregroundStyle(.white)
                    .stickyNoteBadgeStyle(backgroundColor: BookTheme.primary)
                    .tapedBadgeStyle()
            }

            actionButton
                .padding(.top, BookTheme.spacingUnit)

            failureBanner
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BookTheme.screenMargin)
        .notebookCardStyle()
    }

    // MARK: - メモはあるがcachedSummaryが未生成の場合（空状態カード＝背景コンテナ）

    private var notYetGeneratedState: some View {
        VStack(spacing: BookTheme.spacingUnit * 2) {
            Text("まだ要約が作成されていません")
                .font(BookTheme.heading())
                .foregroundStyle(BookTheme.textPrimary)
            actionButton
            failureBanner
        }
        .frame(maxWidth: .infinity)
        .padding(BookTheme.screenMargin)
        .padding(.vertical, BookTheme.spacingUnit * 2)
        .notebookCardStyle()
    }

    // MARK: - エラー状態（ERR-12〜14）

    @ViewBuilder
    private var failureBanner: some View {
        if let failureReason = viewModel.failureReason {
            VStack(spacing: BookTheme.spacingUnit) {
                Text(failureReason.message)
                    .font(BookTheme.body)
                    .foregroundStyle(BookTheme.error)
                    .multilineTextAlignment(.center)

                if failureReason.showsRetryButton {
                    Button("再試行") {
                        Task { await viewModel.generateSummary(context: modelContext) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, BookTheme.spacingUnit)
        }
    }

    // MARK: - メモが0件の場合（空状態カード＝背景コンテナ）

    private var noMemosState: some View {
        VStack(spacing: BookTheme.spacingUnit * 2) {
            Text("まだ要約が作成されていません")
                .font(BookTheme.heading())
                .foregroundStyle(BookTheme.textPrimary)

            Button {
                // メモ0件のため非活性（タップ不可）
            } label: {
                Text("要約を作成する")
            }
            .buttonStyle(PrimaryButtonStyle(isDisabled: true))
            .disabled(true)

            Text("メモを記録すると要約を作成できます")
                .font(BookTheme.caption)
                .foregroundStyle(BookTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(BookTheme.screenMargin)
        .padding(.vertical, BookTheme.spacingUnit * 2)
        .notebookCardStyle()
    }

    // MARK: - 「要約を作成する」／「要約を再作成する」ボタン

    private var actionButton: some View {
        Button {
            Task { await viewModel.generateSummary(context: modelContext) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isGenerating {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isGenerating ? "生成中…" : viewModel.buttonLabel)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isDisabled: viewModel.isGenerating))
        .disabled(viewModel.isGenerating)
    }
}

#Preview("要約あり（Book2）") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    container.mainContext.insert(book)
    return NavigationStack {
        SummaryView(viewModel: SummaryViewModel(book: book))
    }
    .modelContainer(container)
}

#Preview("メモありだが要約未生成") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[0]
    book.memoEntries = [MemoEntry(date: .now, contentItems: ["テストメモ"], book: book)]
    container.mainContext.insert(book)
    return NavigationStack {
        SummaryView(viewModel: SummaryViewModel(book: book))
    }
    .modelContainer(container)
}

#Preview("メモ0件") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[0]
    container.mainContext.insert(book)
    return NavigationStack {
        SummaryView(viewModel: SummaryViewModel(book: book))
    }
    .modelContainer(container)
}
