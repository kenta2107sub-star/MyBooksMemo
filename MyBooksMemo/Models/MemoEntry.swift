import Foundation
import SwiftData

// detailed_design.md 1-1／architecture.md 6.1 の @Model 定義とプロパティ名・型を完全に一致させる。
// 1冊1日1件のメモレコード。
// 1-4：adviceGenerationState／adviceDisplayState／triggerAdviceGeneration()は
// 永続モデルから除去し、BookDetailViewModel（UI専用の一時状態）に移動した。
@Model
final class MemoEntry {
    @Attribute(.unique) var id: UUID
    var date: Date              // Calendar.current.startOfDay(for:) で正規化した「日」の値
    var contentItems: [String]  // FR-03：箇条書きの各項目（保存前に空文字要素を除外済み）
    var dailyAdvice: String?    // FR-09：自動生成される「今日のアドバイス」。値の有無の2値のみ表す
    var book: Book?             // 所属するBookへの参照（`inverse:`なし。カスケード削除は削除処理側で明示的に行う）

    init(id: UUID = UUID(), date: Date, contentItems: [String], book: Book? = nil, dailyAdvice: String? = nil) {
        self.id = id
        self.date = date
        self.contentItems = contentItems
        self.book = book
        self.dailyAdvice = dailyAdvice
    }

    /// FR-04・FR-05・FR-09：Gemini APIへ渡す際は`contentItems`を改行で連結した1つの文字列として扱う
    var joinedContentForAI: String {
        contentItems.joined(separator: "\n")
    }
}
