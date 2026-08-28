import Foundation
import SwiftData

// SCR-01 本棚一覧画面のViewModel。
// detailed_design.md 3-2：ModelContextを保持しfetch()を呼ぶ設計を採用する。
@Observable
final class BookshelfViewModel {
    private let context: ModelContext
    var books: [Book] = []

    var bookPendingDeletion: Book?
    var isShowingDeleteConfirmation = false

    init(context: ModelContext) {
        self.context = context
        fetchBooks()
    }

    func fetchBooks() {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        books = (try? context.fetch(descriptor)) ?? []
    }

    var isEmpty: Bool { books.isEmpty }

    /// SCR-02/03/04からの登録完了時に呼ばれる（FR-01・FR-02）
    func addBook(_ book: Book) {
        context.insert(book)
        try? context.save()
        fetchBooks()
    }

    /// DLG-01：本カードの左スワイプ→「削除」タップ時に呼ばれる
    func requestDelete(_ book: Book) {
        bookPendingDeletion = book
        isShowingDeleteConfirmation = true
    }

    /// 「削除する」タップ → 対象の`Book`を削除する（FR-07）。
    /// SwiftDataの`@Relationship(deleteRule: .cascade)`はApple既知バグにより発動しないため、
    /// memoEntries・conversationLogsを明示的に削除してからBook本体を削除する。
    func confirmDelete() {
        guard let book = bookPendingDeletion else { return }
        book.memoEntries.forEach { context.delete($0) }
        book.conversationLogs.forEach { context.delete($0) }
        context.delete(book)
        try? context.save()
        bookPendingDeletion = nil
        isShowingDeleteConfirmation = false
        fetchBooks()
    }

    /// 「キャンセル」タップ → 何もせず一覧に留まる
    func cancelDelete() {
        bookPendingDeletion = nil
        isShowingDeleteConfirmation = false
    }
}
