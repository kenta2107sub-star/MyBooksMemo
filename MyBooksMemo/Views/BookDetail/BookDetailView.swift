import SwiftUI

// SCR-05：本詳細画面（メモ一覧タブ・要約タブの親コンテナ）。
// 対応FR：FR-03（メモ一覧）, FR-07（メモの削除）, FR-05（要約タブ＝SCR-08）, FR-08（AI対話ログの振り返り閲覧）
// @MainActor：`BookDetailViewModel`・`SummaryViewModel`が`@MainActor`のため、`body`以外の
// 算出プロパティからも安全に参照できるよう、View全体をMainActorに揃える。
@MainActor
struct BookDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: BookDetailViewModel
    @State private var summaryViewModel: SummaryViewModel
    @State private var isShowingMemoEditor = false
    // 「今日のメモを書く」は常に当日、編集アイコンは当該メモの日付を明示的に渡す（FR-03）
    @State private var memoEditorReferenceDate: Date = .now
    // FR-08：振り返りアイコンから開くConversationLog。nilでない間だけSCR-07を読み取り専用で表示する
    @State private var reflectingLog: ConversationLog?

    init(book: Book) {
        _viewModel = State(initialValue: BookDetailViewModel(book: book))
        _summaryViewModel = State(initialValue: SummaryViewModel(book: book))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            DetailTabSelector(selection: $viewModel.selectedTab)
                .padding(.horizontal, BookTheme.screenMargin)
                .padding(.top, BookTheme.spacingUnit)

            Group {
                switch viewModel.selectedTab {
                case .memos:
                    MemoListView(
                        viewModel: viewModel,
                        onWriteToday: {
                            memoEditorReferenceDate = .now
                            isShowingMemoEditor = true
                        },
                        onEditMemo: { memo in
                            memoEditorReferenceDate = memo.date
                            isShowingMemoEditor = true
                        },
                        onReflect: { log in
                            reflectingLog = log
                        }
                    )
                case .summary:
                    SummaryView(viewModel: summaryViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BookTheme.background.ignoresSafeArea())
        .navigationTitle(viewModel.book.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingMemoEditor) {
            MemoEditorView(
                book: viewModel.book,
                referenceDate: memoEditorReferenceDate,
                onAdviceNeeded: { memo in
                    viewModel.triggerAdviceGeneration(for: memo, context: modelContext)
                }
            )
        }
        // FR-08：振り返りアイコン→SCR-07読み取り専用モード。dismiss制限なし（basic_design.md 画面一覧）
        .sheet(item: $reflectingLog) { log in
            AIChatView(conversationLog: log)
        }
        .alert(
            "このメモを削除しますか？",
            isPresented: $viewModel.isShowingDeleteConfirmation,
            presenting: viewModel.memoPendingDeletion
        ) { _ in
            Button("削除する", role: .destructive) {
                withAnimation(.reduceMotionAware(.easeOut(duration: 0.2))) {
                    viewModel.confirmDelete(context: modelContext)
                }
            }
            Button("キャンセル", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: { _ in
            Text("同じ日のAI対話ログも削除され、元に戻せません")
        }
    }

    // ヘッダー領域：書影・タイトル・著者（タブ切り替えに関わらず常時表示）
    private var header: some View {
        HStack(alignment: .top, spacing: BookTheme.spacingUnit * 1.5) {
            BookCoverView(title: viewModel.book.title, imageData: viewModel.book.coverImageData)
                .frame(width: 64, height: 64 * 4 / 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.book.title)
                    .font(BookTheme.heading())
                    .foregroundStyle(BookTheme.textPrimary)
                    .lineLimit(2)

                Text(viewModel.book.author)
                    .font(BookTheme.body)
                    .foregroundStyle(BookTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, BookTheme.screenMargin)
        .padding(.top, BookTheme.spacingUnit)
        .padding(.bottom, BookTheme.spacingUnit * 1.5)
    }
}

/// SCR-05のタブ（メモ一覧／要約）。ネイティブのSegmentedPickerではなく、
/// ブランドカラー（ブックブラウン）で選択中タブを塗りつぶす自前のカプセル型セレクタとして実装し、
/// 標準iOSの灰色ピルにならないようにする。
private struct DetailTabSelector: View {
    @Binding var selection: DetailTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases) { tab in
                Button {
                    withAnimation(.reduceMotionAware(.easeInOut(duration: 0.22))) {
                        selection = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(BookTheme.button(.subheadline))
                        .foregroundStyle(selection == tab ? .white : BookTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius - 2, style: .continuous)
                                    .fill(BookTheme.primary)
                                    .matchedGeometryEffect(id: "detail-tab-highlight", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(BookTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BookTheme.buttonCornerRadius, style: .continuous)
                .strokeBorder(BookTheme.border, lineWidth: 1)
        )
    }
}

#Preview("メモ一覧タブ（Book2）") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    container.mainContext.insert(book)
    return NavigationStack {
        BookDetailView(book: book)
    }
    .modelContainer(container)
}

#Preview("メモ0件・要約未生成（Book1）") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[0]
    container.mainContext.insert(book)
    return NavigationStack {
        BookDetailView(book: book)
    }
    .modelContainer(container)
}
