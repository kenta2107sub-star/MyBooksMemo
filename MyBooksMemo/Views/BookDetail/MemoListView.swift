import SwiftUI

// SCR-05：メモ一覧タブの中身。
// 「今日のメモを書く」ボタン（フローティング・画面下部固定）＋メモカード一覧（日付降順）で構成する。
// Listを使うことでswipeActions（左スワイプ→削除）を標準機能として得つつ、
// 行の背景・区切り線を消してカードが積み重なった見た目に仕立てる。
// @MainActor：`BookDetailViewModel`が`@MainActor`のため、`body`以外の算出プロパティからも
// 安全に参照できるよう、View全体をMainActorに揃える。
@MainActor
struct MemoListView: View {
    @Environment(\.modelContext) private var modelContext
    var viewModel: BookDetailViewModel
    var onWriteToday: () -> Void
    var onEditMemo: (MemoEntry) -> Void
    var onReflect: (ConversationLog) -> Void

    /// フローティングボタンの高さ＋余白の目安。Listの下端がボタンに隠れないよう安全領域として確保する
    private let floatingButtonReservedHeight: CGFloat = 76

    var body: some View {
        // basic_design.md Section 4 SCR-05：「今日のメモを書く」はフローティングボタンとして
        // 画面下部に常時固定表示し、メモ一覧のスクロールに追従させない（ZStackでスクロール
        // コンテンツの上に重ねる）。既存のプライマリボタンのスタイル・配色は変更しない。
        ZStack(alignment: .bottom) {
            Group {
                if viewModel.hasMemos {
                    memoList
                } else {
                    emptyState
                }
            }

            writeTodayButton
                .padding(.horizontal, BookTheme.screenMargin)
                .padding(.bottom, BookTheme.spacingUnit * 2)
        }
        .background(BookTheme.background)
    }

    private var writeTodayButton: some View {
        Button(action: onWriteToday) {
            Text("今日のメモを書く")
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var memoList: some View {
        List {
            // basic_design.md 5.2（2026-08-18更新）：「今日のアドバイス」付箋の背景色は
            // メモ一覧の表示順（日付降順のインデックス）に応じた4色ローテーション。
            // インデックスはenumerated()でMemoCardViewへ渡す
            ForEach(Array(viewModel.sortedMemos.enumerated()), id: \.element.id) { index, memo in
                MemoCardView(
                    memo: memo,
                    conversationLog: viewModel.conversationLog(for: memo),
                    adviceDisplayState: viewModel.adviceDisplayState(for: memo),
                    adviceBackgroundColor: BookTheme.adviceColor(at: index),
                    onReflect: onReflect,
                    onEdit: { onEditMemo(memo) },
                    onDeleteRequested: { viewModel.requestDelete(memo) },
                    onRetryAdvice: { viewModel.triggerAdviceGeneration(for: memo, context: modelContext) }
                )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: BookTheme.screenMargin, bottom: 6, trailing: BookTheme.screenMargin))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            viewModel.requestDelete(memo)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .tint(BookTheme.error)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BookTheme.background)
        // basic_design.md 5.4：「タブとリストの間」のセクション間余白（24〜32pt）を確保する
        // （フローティングボタン化に伴い、従来ボタンが担っていた上部の間隔がなくなったため）
        .padding(.top, BookTheme.sectionSpacing)
        // フローティングボタンに一覧最下部が隠れないよう、スクロール可能領域の下に余白を確保する
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: floatingButtonReservedHeight)
        }
    }

    private var emptyState: some View {
        // basic_design.md 5.0：空状態への手描き風イラスト追加は行わない方針のため、
        // アイコン等は加えず文章と余白のみで丁寧さを表現する。
        VStack(spacing: BookTheme.spacingUnit) {
            Text("まだメモがありません。今日の気づきを書いてみましょう")
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BookTheme.screenMargin * 2)
        }
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#Preview("メモあり") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    container.mainContext.insert(book)
    return NavigationStack {
        MemoListView(
            viewModel: BookDetailViewModel(book: book),
            onWriteToday: {},
            onEditMemo: { _ in },
            onReflect: { _ in }
        )
    }
    .modelContainer(container)
}

#Preview("空の状態") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[0]
    container.mainContext.insert(book)
    return NavigationStack {
        MemoListView(
            viewModel: BookDetailViewModel(book: book),
            onWriteToday: {},
            onEditMemo: { _ in },
            onReflect: { _ in }
        )
    }
    .modelContainer(container)
}
