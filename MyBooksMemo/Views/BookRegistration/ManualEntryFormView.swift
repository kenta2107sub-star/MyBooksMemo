import SwiftUI
import PhotosUI

// SCR-03：本登録画面（手入力）。
// 対応FR：FR-02
// PhotosPickerでの画像選択・読み込みは実装（ローカル処理のため「モックで実装しないこと」の対象外）。
// NDL API・SwiftData永続化は行わない。
struct ManualEntryFormView: View {
    let initialDraft: BookDraft
    var onSaved: (BookDraft) -> Void
    var onCancel: () -> Void

    @State private var viewModel: ManualEntryFormViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @FocusState private var focusedField: Field?

    private enum Field { case title, author }

    init(initialDraft: BookDraft = BookDraft(), onSaved: @escaping (BookDraft) -> Void, onCancel: @escaping () -> Void) {
        self.initialDraft = initialDraft
        self.onSaved = onSaved
        self.onCancel = onCancel
        _viewModel = State(initialValue: ManualEntryFormViewModel(initialDraft: initialDraft))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: BookTheme.sectionSpacing) {
                coverSection

                fieldSection(
                    label: "タイトル（必須）",
                    text: $viewModel.title,
                    placeholder: "例：嫌われる勇気",
                    field: .title,
                    errorMessage: viewModel.titleErrorMessage
                )

                fieldSection(
                    label: "著者",
                    text: $viewModel.author,
                    placeholder: "未入力の場合は「著者不明」として保存",
                    field: .author,
                    errorMessage: nil
                )
            }
            .padding(BookTheme.screenMargin)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            Button("登録する") { handleSave() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, BookTheme.screenMargin)
                .padding(.vertical, BookTheme.spacingUnit)
                .background(.ultraThinMaterial)
        }
        .background(BookTheme.background.ignoresSafeArea())
        .navigationTitle("本を登録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("キャンセル") { onCancel() }
                    .foregroundStyle(BookTheme.primary)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        await MainActor.run { viewModel.coverImageData = data }
                    } else {
                        await MainActor.run { viewModel.handleImageLoadFailure() }
                    }
                } catch {
                    await MainActor.run { viewModel.handleImageLoadFailure() }
                }
            }
        }
        // DLG-03
        .alert(
            "画像を読み込めませんでした。表紙なしで登録しますか？",
            isPresented: $viewModel.isShowingImageLoadFailureConfirm
        ) {
            Button("はい") { viewModel.continueWithoutCover() }
            Button("いいえ", role: .cancel) { viewModel.retryImageSelection() }
        }
    }

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: BookTheme.spacingUnit) {
            Text("表紙画像")
                .font(BookTheme.button(.subheadline))
                .foregroundStyle(BookTheme.textPrimary)

            HStack(spacing: BookTheme.spacingUnit * 1.5) {
                BookCoverView(title: viewModel.title.isEmpty ? " " : viewModel.title, imageData: viewModel.coverImageData)
                    .frame(width: 80, height: 80 * 4 / 3)
                    .animation(.reduceMotionAware(.easeInOut(duration: 0.25)), value: viewModel.coverImageData)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("画像を選択")
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer(minLength: 0)
            }
        }
    }

    private func fieldSection(
        label: String,
        text: Binding<String>,
        placeholder: String,
        field: Field,
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BookTheme.button(.subheadline))
                .foregroundStyle(BookTheme.textPrimary)

            TextField(placeholder, text: text)
                .font(BookTheme.body)
                .foregroundStyle(BookTheme.textPrimary)
                .padding(12)
                .background(BookTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: BookTheme.textFieldCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BookTheme.textFieldCornerRadius, style: .continuous)
                        .strokeBorder(
                            errorMessage != nil ? BookTheme.error : (focusedField == field ? BookTheme.primary : BookTheme.border),
                            lineWidth: focusedField == field || errorMessage != nil ? 2 : 1
                        )
                )
                .focused($focusedField, equals: field)
                .submitLabel(field == .title ? .next : .done)

            if let errorMessage {
                Text(errorMessage)
                    .font(BookTheme.caption)
                    .foregroundStyle(BookTheme.error)
            }
        }
    }

    private func handleSave() {
        guard viewModel.validate() else { return }
        onSaved(viewModel.draft)
    }
}

#Preview("新規（値なし）") {
    NavigationStack {
        ManualEntryFormView(onSaved: { _ in }, onCancel: {})
    }
}

#Preview("SCR-04から修正で遷移（値あり）") {
    NavigationStack {
        ManualEntryFormView(
            initialDraft: BookDraft(title: "嫌われる勇気", author: "岸見一郎, 古賀史健"),
            onSaved: { _ in },
            onCancel: {}
        )
    }
}
