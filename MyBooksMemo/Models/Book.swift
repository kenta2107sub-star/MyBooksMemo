import Foundation
import SwiftData

// detailed_design.md 1-1／architecture.md 6.1 の @Model 定義とプロパティ名・型を完全に一致させる。
@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var isbn: String?                  // 手入力登録時はnilの場合あり
    var coverImageData: Data?          // NDL取得画像 or PhotosPickerで選択した画像をローカル保存
    var createdAt: Date
    var cachedSummary: String?               // FR-05：要約キャッシュ
    var cachedSummaryGeneratedAt: Date?      // FR-05：要約の最終生成日時

    // 注意：SwiftDataの`.cascade`削除ルールはApple既知バグ（Apple Developer Forums
    // thread 740649 等で報告）により、`inverse:`の有無に関わらずcontext.save()経由の
    // カスケード削除が発動しない。そのためdeleteRule: .cascadeは保険として残すのみで、
    // 実際の削除処理はBookshelfViewModel.confirmDelete()が明示的に行う。
    // Book側配列への追加も呼び出し元で手動で行う
    // （MemoEditorViewModel.save() / AIChatViewModel.saveIfNeeded() 参照）。
    @Relationship(deleteRule: .cascade)
    var memoEntries: [MemoEntry] = []

    @Relationship(deleteRule: .cascade)
    var conversationLogs: [ConversationLog] = []

    init(
        id: UUID = UUID(),
        title: String,
        author: String,
        isbn: String? = nil,
        coverImageData: Data? = nil,
        createdAt: Date = .now,
        cachedSummary: String? = nil,
        cachedSummaryGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
        self.coverImageData = coverImageData
        self.createdAt = createdAt
        self.cachedSummary = cachedSummary
        self.cachedSummaryGeneratedAt = cachedSummaryGeneratedAt
    }
}
