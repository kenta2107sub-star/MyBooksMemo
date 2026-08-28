import Foundation
import SwiftData

/// SCR-06の入力フォーム1行分（箇条書きの1項目）。配列の要素として安定したidを持たせることで、
/// フォームの追加・削除時にSwiftUIの`ForEach`/`TextField`のフォーカス・状態が正しく維持される。
struct MemoFormItem: Identifiable, Equatable {
    let id = UUID()
    var text: String = ""
}

// SCR-06 メモ入力画面のViewModel。
// FR-03（2026-08-18更新）：単一テキストエリアから箇条書き（複数の1行フォーム）方式に変更。
// 当日分メモが既存の場合は`contentItems`の要素数と同じ数のフォームを読み込み上書き編集、
// なければ空欄フォーム1つから新規作成する（1日1件・後勝ち上書きのルールは変更なし）。
@Observable
final class MemoEditorViewModel {
    let book: Book
    let normalizedDate: Date
    var items: [MemoFormItem]
    var contentErrorMessage: String?

    private let existingMemo: MemoEntry?

    init(book: Book, referenceDate: Date = .now) {
        self.book = book
        let normalized = Calendar.current.startOfDay(for: referenceDate)
        self.normalizedDate = normalized

        if let existing = book.memoEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: normalized) }) {
            self.existingMemo = existing
            self.items = existing.contentItems.isEmpty
                ? [MemoFormItem()]
                : existing.contentItems.map { MemoFormItem(text: $0) }
        } else {
            self.existingMemo = nil
            self.items = [MemoFormItem()]
        }
    }

    /// 「本日分を編集しています」の任意表示に使う（basic_design.md SCR-06補足）
    var isEditingExistingMemo: Bool { existingMemo != nil }

    /// 「{本のタイトル}・{yyyy年M月d日}」形式（basic_design.md SCR-06表示データ）
    var headerLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return "\(book.title)・\(formatter.string(from: normalizedDate))"
    }

    /// 「＋」ボタン：新しい空欄フォームを一番下に追加する
    func addItem() {
        items.append(MemoFormItem())
    }

    /// フォームの削除ボタン：そのフォームを削除する。最後の1つを削除した場合は
    /// 自動的に空欄のフォームを1つ表示した状態を維持する（入力フォームが0個になる状態は作らない）
    func removeItem(id: UUID) {
        items.removeAll { $0.id == id }
        if items.isEmpty {
            items = [MemoFormItem()]
        }
    }

    /// ERR-08：「メモを入力してください」。各フォームの空文字（前後の空白のみを含む場合を含む）を
    /// 除外した結果、1件も残らない場合にエラーとする
    @discardableResult
    func validate() -> Bool {
        let hasAnyContent = items.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasAnyContent {
            contentErrorMessage = "メモを入力してください"
            return false
        }
        contentErrorMessage = nil
        return true
    }

    /// 保存して保存済みのMemoEntryを返す（新規作成 or 上書き編集）。
    /// 空文字（前後の空白のみを含む場合を含む）の項目は自動的に除外し、
    /// 残った項目をフォームの表示順（上から順）のまま`contentItems`として保存する。
    /// detailed_design.md 3-1：保存先はModelContext経由（SwiftData永続化）にする。
    func save(context: ModelContext) -> MemoEntry {
        let filteredItems = items
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let existing = existingMemo {
            existing.contentItems = filteredItems
            try? context.save()
            return existing
        } else {
            let newMemo = MemoEntry(date: normalizedDate, contentItems: filteredItems)
            context.insert(newMemo)
            newMemo.book = book
            book.memoEntries.append(newMemo)
            try? context.save()
            return newMemo
        }
    }
}
