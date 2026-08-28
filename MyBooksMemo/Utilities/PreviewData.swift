import Foundation
import SwiftData

// detailed_design.md 3-4（表8）：`MockData.swift`削除に伴う置き換え。
// #Preview専用のシードデータ生成ヘルパー。本体コード（View/ViewModel/Services）から
// 参照してはならない。NDL API・Gemini API・SwiftDataへの実通信は行わない。
enum PreviewData {

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components) ?? .now
    }

    /// 単体コンポーネントのプレビュー用に、ModelContextへ挿入せず単独で使えるBook 3冊を作る
    /// （@Modelインスタンスはコンテキストに挿入しなくても通常のSwiftオブジェクトとして扱える）。
    static func makeBooks() -> [Book] {
        let book1 = Book(
            title: "嫌われる勇気",
            author: "岸見一郎, 古賀史健",
            isbn: "9784478025819",
            createdAt: date(2026, 7, 20)
        )

        let book2 = Book(
            title: "7つの習慣",
            author: "スティーブン・R・コヴィー",
            isbn: "9784863940246",
            createdAt: date(2026, 7, 25),
            cachedSummary: """
            【この本から得た気づき】
            ・「主体的である」という考え方について、3回のメモで繰り返し言及している
            ・7/28の対話で「反応する前に一呼吸置く」という具体的な行動目標が明確化された
            """,
            cachedSummaryGeneratedAt: date(2026, 7, 30)
        )

        let book3 = Book(
            title: "人を動かす",
            author: "デール・カーネギー",
            createdAt: date(2026, 8, 1)
        )

        let memo1 = MemoEntry(
            date: date(2026, 7, 30),
            contentItems: ["「主体的である」の章を読み返した", "反応的な自分に気づけた一日だった"],
            book: book2
        )
        let memo2 = MemoEntry(
            date: date(2026, 7, 28),
            contentItems: ["第一の習慣について", "刺激と反応の間には選択の自由がある、という一文が刺さった"],
            book: book2,
            dailyAdvice: "一呼吸置く習慣を、まずは1日1回から試してみましょう。指摘を受けた直後の数秒に意識を向けるだけでも、選べる態度の幅が変わってきます。"
        )
        let memo3 = MemoEntry(
            date: date(2026, 7, 20),
            contentItems: ["読み始め", "7つの習慣という言葉は知っていたが、内容はほぼ知らなかった"],
            book: book2
        )
        book2.memoEntries = [memo1, memo2, memo3]

        let conversationLog = ConversationLog(
            date: date(2026, 7, 28),
            turns: [
                ConversationTurn(
                    question: "「刺激と反応の間には選択の自由がある」とありますが、直近で「反応」してしまったと感じた場面はありますか？",
                    answer: "後輩に強い口調で指摘されて、思わずイラっとした態度を返してしまった"
                ),
                ConversationTurn(
                    question: "そのとき、一呼吸置けていたら、どんな態度を選べていたと思いますか？",
                    answer: "一度深呼吸して、指摘の内容そのものに向き合えていたかもしれない"
                )
            ],
            book: book2
        )
        book2.conversationLogs = [conversationLog]

        return [book1, book2, book3]
    }

    /// `BookshelfView`の#Previewなど、実際に`ModelContext.fetch()`を要する場合に使う
    /// in-memory（アプリ再起動で消える）ModelContainer。
    @MainActor
    static func makeContainer(seeded: Bool = true) -> ModelContainer {
        let schema = Schema([Book.self, MemoEntry.self, ConversationLog.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: configuration)
        if seeded {
            let context = container.mainContext
            makeBooks().forEach { context.insert($0) }
            try? context.save()
        }
        return container
    }
}
