import Foundation
import SwiftData

// detailed_design.md 1-1／architecture.md 6.1 の ConversationTurn / ConversationLog 定義に合わせる。
// 1-4：ConversationTurnはIdentifiable準拠を外し、Codableのみに戻す
// （Gemini APIへ送信するJSONに無関係なidフィールドを混入させないため）。
struct ConversationTurn: Codable {
    var question: String
    var answer: String
}

@Model
final class ConversationLog {
    @Attribute(.unique) var id: UUID
    var date: Date                 // MemoEntry.date と同じ正規化ルール
    var turns: [ConversationTurn]
    var book: Book?

    init(id: UUID = UUID(), date: Date, turns: [ConversationTurn] = [], book: Book? = nil) {
        self.id = id
        self.date = date
        self.turns = turns
        self.book = book
    }
}
