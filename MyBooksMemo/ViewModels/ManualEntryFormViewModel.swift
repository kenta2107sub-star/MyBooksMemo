import Foundation

// SCR-03 本登録画面（手入力）のViewModel。
// FR-02からの遷移時はinitialDraftに取得済み情報（SCR-02/SCR-04経由）を渡し初期値として編集可能にする。
@Observable
final class ManualEntryFormViewModel {
    var title: String
    var author: String
    var coverImageData: Data?

    var titleErrorMessage: String?
    var isShowingImageLoadFailureConfirm = false

    init(initialDraft: BookDraft = BookDraft()) {
        self.title = initialDraft.title
        self.author = initialDraft.author
        self.coverImageData = initialDraft.coverImageData
    }

    /// 「登録する」タップ時のバリデーション（ERR-06：「タイトルを入力してください」）
    @discardableResult
    func validate() -> Bool {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            titleErrorMessage = "タイトルを入力してください"
            return false
        }
        titleErrorMessage = nil
        return true
    }

    var draft: BookDraft {
        BookDraft(title: title, author: author, coverImageData: coverImageData)
    }

    /// PhotosPickerでの画像読み込みに失敗した場合（ERR-07 / DLG-03）
    func handleImageLoadFailure() {
        isShowingImageLoadFailureConfirm = true
    }

    /// DLG-03「はい」：表紙なしで登録を続行する
    func continueWithoutCover() {
        coverImageData = nil
        isShowingImageLoadFailureConfirm = false
    }

    /// DLG-03「いいえ」：画像選択をやり直せる状態のままSCR-03に留まる
    func retryImageSelection() {
        isShowingImageLoadFailureConfirm = false
    }
}
