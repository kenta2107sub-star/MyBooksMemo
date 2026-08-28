import SwiftUI
import SwiftData

// SCR-01：本棚一覧画面。アプリのホーム画面（NavigationStackのルート）。
// 対応FR：FR-01（登録導線）, FR-02（登録導線）, FR-07（本の削除）
struct BookshelfView: View {
    @State private var viewModel: BookshelfViewModel
    @State private var isShowingRegistrationOptions = false
    @State private var registrationEntryPoint: RegistrationFlowView.EntryPoint?
    // BookCardView自身がドラッグジェスチャー（左スワイプ削除）を持つため、
    // NavigationLinkでラップするとジェスチャー競合でタップ遷移が反応しないことがある。
    // そのためNavigationLinkは使わず、パス配列を直接操作する明示的な画面遷移にする。
    @State private var path: [Book] = []

    private let columns = [
        GridItem(.flexible(), spacing: BookTheme.screenMargin),
        GridItem(.flexible(), spacing: BookTheme.screenMargin)
    ]

    /// `modelContext`はアプリ起動時（`MyBooksMemoApp`）に`ModelContainer.mainContext`から
    /// 明示的に渡す。`@Environment(\.modelContext)`はView.body評価時点まで解決されないため、
    /// `@State`の初期値式（BookshelfViewModelの生成）内では参照できないことを踏まえた設計。
    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: BookshelfViewModel(context: modelContext))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    bookGrid
                }
            }
            .background(BookTheme.background.ignoresSafeArea())
            .navigationTitle("わたしの本棚")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingRegistrationOptions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(BookTheme.primary)
                    .accessibilityLabel("本を登録する")
                }
            }
            .confirmationDialog(
                "本を登録する",
                isPresented: $isShowingRegistrationOptions,
                titleVisibility: .visible
            ) {
                Button("バーコードでスキャンする") { registrationEntryPoint = .scan }
                Button("手入力で登録する") { registrationEntryPoint = .manual }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(item: $registrationEntryPoint) { entryPoint in
                RegistrationFlowView(entryPoint: entryPoint) { newBook in
                    withAnimation(.reduceMotionAware(.easeOut(duration: 0.25))) {
                        viewModel.addBook(newBook)
                    }
                }
            }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .alert(
                Text("『\(viewModel.bookPendingDeletion?.title ?? "")』を削除しますか？"),
                isPresented: $viewModel.isShowingDeleteConfirmation,
                presenting: viewModel.bookPendingDeletion
            ) { _ in
                Button("削除する", role: .destructive) {
                    withAnimation(.reduceMotionAware(.easeOut(duration: 0.25))) {
                        viewModel.confirmDelete()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    viewModel.cancelDelete()
                }
            } message: { _ in
                Text("この本に紐づくメモ・AI対話ログ・要約もすべて削除され、元に戻せません")
            }
        }
    }

    private var bookGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(viewModel.books) { book in
                    BookCardView(
                        book: book,
                        onTap: { path.append(book) },
                        onDeleteRequested: { viewModel.requestDelete(book) }
                    )
                }
            }
            .padding(.horizontal, BookTheme.screenMargin)
            .padding(.top, BookTheme.spacingUnit)
            .padding(.bottom, BookTheme.sectionSpacing)
        }
    }

    private var emptyState: some View {
        // basic_design.md 5.0：空状態への手描き風イラスト追加は行わない方針のため、
        // アイコン等は加えず文章と余白のみで丁寧さを表現する。
        VStack(spacing: BookTheme.spacingUnit * 2) {
            Text("まだ本が登録されていません")
                .font(BookTheme.heading())
                .foregroundStyle(BookTheme.textPrimary)

            Text("右上の＋から最初の1冊を登録しましょう")
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, BookTheme.screenMargin * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("通常状態") {
    let container = PreviewData.makeContainer()
    return BookshelfView(modelContext: container.mainContext)
        .modelContainer(container)
}

#Preview("空の状態") {
    let container = PreviewData.makeContainer(seeded: false)
    return BookshelfView(modelContext: container.mainContext)
        .modelContainer(container)
}
