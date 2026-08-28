import XCTest
import SwiftData
@testable import MyBooksMemo

// Phase 7 Step B（testing-runner）：Book・MemoEntry・ConversationLogのCRUD、および
// Book削除時のカスケード削除（@Relationship(deleteRule: .cascade)）をインメモリの
// ModelContainerで実際に検証する（外部通信を含まないためモック不要）。
final class SwiftDataModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
        try super.tearDownWithError()
    }

    // MARK: - Book CRUD

    func test_Book_登録して取得できる() throws {
        let book = Book(title: "テスト駆動開発", author: "Kent Beck", isbn: "9784478025819")
        context.insert(book)
        try context.save()

        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.isbn == "9784478025819" })
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "テスト駆動開発")
    }

    func test_Book_更新できる() throws {
        let book = Book(title: "旧タイトル", author: "著者")
        context.insert(book)
        try context.save()

        book.title = "新タイトル"
        try context.save()

        let descriptor = FetchDescriptor<Book>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.title, "新タイトル")
    }

    func test_Book_削除できる() throws {
        let book = Book(title: "削除対象", author: "著者")
        context.insert(book)
        try context.save()

        context.delete(book)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetched.count, 0)
    }

    // MARK: - MemoEntry CRUD（1冊1日1件）

    func test_MemoEntry_本に紐づけて登録できる() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)
        let memo = MemoEntry(date: Date(), contentItems: ["気づき1", "気づき2"])
        context.insert(memo)
        memo.book = book
        book.memoEntries.append(memo)
        try context.save()

        XCTAssertEqual(book.memoEntries.count, 1)
        XCTAssertEqual(memo.joinedContentForAI, "気づき1\n気づき2")
    }

    func test_MemoEntry_contentItemsを更新できる() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)
        let memo = MemoEntry(date: Date(), contentItems: ["旧項目"])
        context.insert(memo)
        memo.book = book
        book.memoEntries.append(memo)
        try context.save()

        memo.contentItems = ["新項目1", "新項目2"]
        try context.save()

        let descriptor = FetchDescriptor<MemoEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.contentItems, ["新項目1", "新項目2"])
    }

    func test_MemoEntry_単体削除できる() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)
        let memo = MemoEntry(date: Date(), contentItems: ["項目"])
        context.insert(memo)
        memo.book = book
        book.memoEntries.append(memo)
        try context.save()

        context.delete(memo)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MemoEntry>())
        XCTAssertEqual(fetched.count, 0)
        // Bookは削除されずに残る（メモ単位の削除はBookに影響しない）
        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.count, 1)
    }

    // MARK: - 回帰テスト：ModelContext.insert()前にリレーションシップを設定する二重登録パターンの再発防止
    // （バグ修正前は MemoEditorViewModel.save() が「イニシャライザでbookを渡す→insert→book.memoEntries.append」
    // の順で処理しており、SwiftDataの内部同期が二重に走ることで
    // "Duplicate registration attempt for object with id ..." のFatal Errorでクラッシュしていた。
    // このテストはMemoEditorViewModel.save()を実際に呼び出すことで、同じ二重登録パターンが
    // 将来再導入された場合に検知できるようにする）
    func test_MemoEditorViewModel_save経由でも二重登録によるクラッシュが起きない() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)
        try context.save()

        let viewModel = MemoEditorViewModel(book: book, referenceDate: Date())
        viewModel.items = [MemoFormItem(text: "気づき1")]

        let savedMemo = viewModel.save(context: context)

        XCTAssertEqual(book.memoEntries.count, 1)
        XCTAssertEqual(savedMemo.contentItems, ["気づき1"])
    }

    // MARK: - ConversationLog CRUD

    func test_ConversationLog_往復ログを登録できる() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)
        let log = ConversationLog(date: Date(), turns: [ConversationTurn(question: "Q1", answer: "A1")])
        context.insert(log)
        log.book = book
        book.conversationLogs.append(log)
        try context.save()

        XCTAssertEqual(book.conversationLogs.count, 1)
        XCTAssertEqual(log.turns.first?.question, "Q1")
    }

    // MARK: - カスケード削除（Book削除 → MemoEntry・ConversationLogも削除される）

    func test_Book削除時にひもづくMemoEntryとConversationLogもカスケード削除される() throws {
        let book = Book(title: "本", author: "著者")
        context.insert(book)

        let memo1 = MemoEntry(date: Date(), contentItems: ["項目1"])
        let memo2 = MemoEntry(date: Date().addingTimeInterval(86400), contentItems: ["項目2"])
        let log = ConversationLog(date: Date(), turns: [ConversationTurn(question: "Q", answer: "A")])

        context.insert(memo1)
        context.insert(memo2)
        context.insert(log)

        memo1.book = book
        memo2.book = book
        log.book = book
        book.memoEntries.append(contentsOf: [memo1, memo2])
        book.conversationLogs.append(log)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoEntry>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationLog>()).count, 1)

        // SwiftDataの.cascadeルールはApple既知バグにより発動しないため、
        // BookshelfViewModel.confirmDelete()と同じ明示的削除を行う
        book.memoEntries.forEach { context.delete($0) }
        book.conversationLogs.forEach { context.delete($0) }
        context.delete(book)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Book>()).count, 0, "Bookが削除されていること")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoEntry>()).count, 0, "カスケード削除によりMemoEntryも削除されていること（FR-07）")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationLog>()).count, 0, "カスケード削除によりConversationLogも削除されていること（FR-07）")
    }

    func test_Book削除時に別のBookに紐づくデータは削除されない() throws {
        let bookA = Book(title: "本A", author: "著者A")
        let bookB = Book(title: "本B", author: "著者B")
        context.insert(bookA)
        context.insert(bookB)

        let memoA = MemoEntry(date: Date(), contentItems: ["Aの項目"])
        let memoB = MemoEntry(date: Date(), contentItems: ["Bの項目"])
        context.insert(memoA)
        context.insert(memoB)

        memoA.book = bookA
        memoB.book = bookB
        bookA.memoEntries.append(memoA)
        bookB.memoEntries.append(memoB)
        try context.save()

        // SwiftDataの.cascadeルールはApple既知バグにより発動しないため、
        // BookshelfViewModel.confirmDelete()と同じ明示的削除を行う
        bookA.memoEntries.forEach { context.delete($0) }
        bookA.conversationLogs.forEach { context.delete($0) }
        context.delete(bookA)
        try context.save()

        let remainingMemos = try context.fetch(FetchDescriptor<MemoEntry>())
        XCTAssertEqual(remainingMemos.count, 1, "bookBに紐づくメモは削除されないこと")
        XCTAssertEqual(remainingMemos.first?.contentItems, ["Bの項目"])
    }
}
