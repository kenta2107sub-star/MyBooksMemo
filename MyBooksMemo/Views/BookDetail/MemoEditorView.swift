import SwiftUI

// SCR-06：メモ入力画面。
// 対応FR：FR-03, FR-09（対話スキップ時のアドバイス生成トリガー元）
// 2026-08-18更新：単一テキストエリアから箇条書き（複数の1行フォーム）方式に全面改訂。
// 保存ボタンはナビゲーションバー右から画面下部固定のフローティングボタンに変更した
// （SCR-05「今日のメモを書く」ボタンと同じ配置パターン）。
// 保存後は確認ダイアログ「AIと少し話してみますか？」（DLG-04）→ SCR-07（AI対話）への導線を持つ。
struct MemoEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: MemoEditorViewModel
    @State private var isShowingAIChatPrompt = false
    @State private var isShowingAIChat = false
    @State private var savedMemo: MemoEntry?
    @FocusState private var focusedItemID: UUID?
    @Environment(\.dismiss) private var dismiss

    /// FR-09：メモ保存フロー完了時（対話スキップ時／対話終了時）にアドバイス生成をトリガーする。
    /// detailed_design.md 1-4・3-2：状態はBookDetailViewModelが保持するため、呼び出し元
    /// （BookDetailView）から渡されたクロージャ経由で`triggerAdviceGeneration(for:context:)`を呼ぶ。
    var onAdviceNeeded: (MemoEntry) -> Void

    /// フローティング保存ボタンに一覧最下部が隠れないよう確保する安全領域の高さ
    private let floatingButtonReservedHeight: CGFloat = 76

    /// `referenceDate`省略時は当日（「今日のメモを書く」からの遷移）。
    /// メモカードの編集アイコンからの遷移では、当該メモの`date`を明示的に渡す。
    init(book: Book, referenceDate: Date = .now, onAdviceNeeded: @escaping (MemoEntry) -> Void = { _ in }) {
        _viewModel = State(initialValue: MemoEditorViewModel(book: book, referenceDate: referenceDate))
        self.onAdviceNeeded = onAdviceNeeded
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            // basic_design.md Section 4 SCR-06：保存ボタンは画面下部に常に浮いた状態で表示され、
            // フォーム群のスクロール位置に関わらず常に同じ位置に固定表示され続ける
            // （ZStackでスクロールコンテンツの上に重ねて配置し、スクロールに追従しない）。
            ZStack(alignment: .bottom) {
                formScrollContent
                saveButton
                    .padding(.horizontal, BookTheme.screenMargin)
                    .padding(.bottom, BookTheme.spacingUnit * 2)
            }
            .background(BookTheme.background.ignoresSafeArea())
            .navigationTitle("今日のメモ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .foregroundStyle(BookTheme.primary)
                }
            }
            // DLG-04
            .alert("AIと少し話してみますか？", isPresented: $isShowingAIChatPrompt) {
                Button("はい") { isShowingAIChat = true }
                Button("いいえ", role: .cancel) {
                    // FR-09 トリガー経路A：対話をスキップした場合、メモ内容のみでアドバイス生成を
                    // バックグラウンドでトリガーする。画面遷移（dismiss）は生成完了を待たずに行う
                    if let savedMemo {
                        onAdviceNeeded(savedMemo)
                    }
                    dismiss()
                }
            }
            .sheet(isPresented: $isShowingAIChat, onDismiss: { dismiss() }) {
                if let savedMemo {
                    AIChatView(book: viewModel.book, memo: savedMemo, onAdviceNeeded: onAdviceNeeded)
                }
            }
        }
    }

    // MARK: - スクロールするフォーム本体

    private var formScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BookTheme.spacingUnit * 1.5) {
                Text(viewModel.headerLabel)
                    .font(BookTheme.caption)
                    .foregroundStyle(BookTheme.textSecondary)

                if viewModel.isEditingExistingMemo {
                    // 装飾のセカンダリカラー（アンバー）はテキスト色として使うとコントラスト比が
                    // 4.5:1を下回るため、文字色にはプライマリカラーを使う（5.31:1）
                    Text("本日分を編集しています")
                        .font(BookTheme.caption)
                        .foregroundStyle(BookTheme.primary)
                }

                formRows

                if let error = viewModel.contentErrorMessage {
                    Text(error)
                        .font(BookTheme.caption)
                        .foregroundStyle(BookTheme.error)
                }
            }
            .padding(BookTheme.screenMargin)
        }
        // フローティング保存ボタンにフォーム最下部が隠れないよう、スクロール可能領域の下に余白を確保する
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: floatingButtonReservedHeight)
        }
    }

    // MARK: - 箇条書き入力フォーム群

    private var formRows: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach($viewModel.items) { $item in
                formRow(text: $item.text, id: item.id)
            }

            addButton
        }
    }

    private func formRow(text: Binding<String>, id: UUID) -> some View {
        // basic_design.md 2026-08-18追加・再調整：1行のTextFieldから、複数行入力可能な
        // テキストエリア相当に変更。ドラッグ等の手動リサイズではなく、入力内容に応じて
        // 下方向へ自動的に高さが伸びる自動リサイズ方式とする（`axis: .vertical` + `lineLimit(5...)`）。
        // 初期表示時点で5行分の高さを確保し、それを超えたらさらに自動的に伸びる
        HStack(alignment: .top, spacing: 8) {
            // basic_design.md 5.4.5／5.4.6：各入力フォームの背景に方眼罫線・紙テクスチャを敷き、
            // ノートに書いているような入力体験にする。罫線・テクスチャはテキストより下のレイヤーに
            // 描画し、入力文字の可読性を最優先する（SCR-05／SCR-08より薄い既定濃さを使う）
            TextField("箇条書きの項目を入力", text: text, axis: .vertical)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textPrimary)
                .lineLimit(5...)
                .padding(10)
                .focused($focusedItemID, equals: id)
                .notebookTextFieldBackground()
                .overlay(
                    RoundedRectangle(cornerRadius: BookTheme.textFieldCornerRadius, style: .continuous)
                        .strokeBorder(
                            focusedItemID == id ? BookTheme.primary : BookTheme.border,
                            lineWidth: focusedItemID == id ? 2 : 1
                        )
                )

            Button {
                withAnimation(.reduceMotionAware(.easeOut(duration: 0.18))) {
                    viewModel.removeItem(id: id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BookTheme.error)
            .accessibilityLabel("この項目を削除")
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(.reduceMotionAware(.easeOut(duration: 0.18))) {
                viewModel.addItem()
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BookTheme.primary)
        .accessibilityLabel("新しい項目を追加")
    }

    // MARK: - フローティング保存ボタン

    private var saveButton: some View {
        Button("保存") { handleSave() }
            .buttonStyle(PrimaryButtonStyle())
    }

    private func handleSave() {
        guard viewModel.validate() else { return }
        savedMemo = viewModel.save(context: modelContext)
        isShowingAIChatPrompt = true
    }
}

#Preview("新規メモ") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[0]
    container.mainContext.insert(book)
    return MemoEditorView(book: book)
        .modelContainer(container)
}

#Preview("上書き編集（今日の日付にメモがある想定）") {
    let container = PreviewData.makeContainer(seeded: false)
    let book = PreviewData.makeBooks()[1]
    book.memoEntries.append(
        MemoEntry(date: .now, contentItems: ["プレビュー確認用の既存メモ項目1", "既存メモ項目2"], book: book)
    )
    container.mainContext.insert(book)
    return MemoEditorView(book: book)
        .modelContainer(container)
}
