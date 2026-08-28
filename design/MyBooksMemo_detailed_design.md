# 詳細設計書

> **プロジェクト名**：MyBooksMemo（読書メモ・言語化トレーニングアプリ）
> **対象フェーズ**：Phase 1（MVP）本実装用
> **このドキュメントの用途**：Claude Codeが本実装（SwiftDataモデル・Cloudflare Workers API・iOSコンポーネント・型定義）を行うための仕様書。Phase 3・Phase 4で実装済みのモックコード（`MyBooksMemo/`配下）から逆算し、モックのまま踏襲してよい箇所と、本実装で置き換え・追加が必要な箇所を明確に分離している。
> **逆算元のファイル**：
> - `MyBooksMemo_basic_design.md`（データモデル・画面仕様・エラー定義・確認ダイアログ文言）
> - `MyBooksMemo_requirements.md`（FR-01〜FR-09・NF-01〜NF-06・エラー定義の一次情報）
> - モックコード（`MyBooksMemo/Models/`・`MyBooksMemo/Views/`・`MyBooksMemo/ViewModels/`・`MyBooksMemo/Utilities/`）
> **関連ドキュメント**：
> - `MyBooksMemo_architecture.md`（技術スタック・システム構成・ディレクトリ構成・SwiftDataモデル方針・環境変数）
> **次のステップ**：本ドキュメントとarchitecture.mdをClaude Codeに渡して本実装（Phase 7）を開始する

---

## 1. DBスキーマ（SwiftDataモデル）

> 本アプリはSwiftDataによるローカル永続化のみで、外部DB・ORMは使用しない（architecture.md 1.1）。モックコードは`@Observable`のみを付与したin-memoryクラスとして実装済みのため、本実装では`@Model`マクロの付与とSwiftData永続化への差し替えが主な作業になる。

### 1-1. モデル定義（本実装版）

architecture.md 6.1で確定済みのプロパティ名・型を完全に維持する。モックコードとの差分は「1-4 モックからの変更点」に集約する。

```swift
// Models/Book.swift
import Foundation
import SwiftData

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

    // 注意：`inverse:`付きのcascade削除ルールはSwiftData自体の既知バグ（Apple Developer Forums
    // thread 740649等）により、context.save()経由の削除が発動しないケースがある。
    // 本実装ではSwiftDataのcascade機構に頼らず、削除処理側（1-3参照）で明示的に子を削除する。
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
```

```swift
// Models/MemoEntry.swift
import Foundation
import SwiftData

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
```

```swift
// Models/ConversationLog.swift
import Foundation
import SwiftData

struct ConversationTurn: Codable {
    var question: String
    var answer: String
}

@Model
final class ConversationLog {
    @Attribute(.unique) var id: UUID
    var date: Date                       // MemoEntry.dateと同じ正規化ルール
    var turns: [ConversationTurn]        // Codable構造体配列。SwiftDataがそのまま属性として永続化する
    var book: Book?

    init(id: UUID = UUID(), date: Date, turns: [ConversationTurn] = [], book: Book? = nil) {
        self.id = id
        self.date = date
        self.turns = turns
        self.book = book
    }
}
```

> `ConversationTurn`はモックの`Identifiable`準拠（UI表示用の`id: UUID = UUID()`）を外し、`Codable`のみに戻している。理由は1-4参照。UI側（`ChatMessage`等）で必要な識別子はView層のラッパー型が別途持つため、永続化モデル自体に持たせる必要はない。

### 1-2. ER図

```
Book ||--o{ MemoEntry        : "1冊の本は複数のメモを持つ（削除処理側で明示的に連動削除）"
Book ||--o{ ConversationLog  : "1冊の本は複数の対話ログを持つ（削除処理側で明示的に連動削除）"

MemoEntry と ConversationLog は直接のリレーションシップを持たない
（同一book・同一dateの組み合わせでアプリケーションロジックとして関連付ける）
```

### 1-3. リレーションシップとカスケード削除の設計

> **2026-08-27追記**：`@Relationship(deleteRule: .cascade, inverse:)`によるSwiftData自動カスケード削除は、実機・シミュレータ双方の単体テスト（`SwiftDataModelTests`）で検証した結果、`inverse:`の有無に関わらず`context.delete()`＋`context.save()`経由では発動しないことを確認した（SwiftData自体の既知バグ。Apple Developer Forums thread 740649等で同様の報告あり）。そのため本実装では`.cascade`ルールを削除の実効手段として使わず、**削除処理側のアプリケーションコードで子オブジェクトを明示的に削除する**方式に統一する。`deleteRule: .cascade`のアノテーション自体は残すが（将来SwiftData側の不具合が解消した場合の保険であり、明示的削除と併用しても副作用はない）、実効性はアプリケーションコード側の処理に依存する。

| リレーションシップ | deleteRule | 実装箇所（実効的な削除処理） | 対応FR |
|---|---|---|---|
| `Book.memoEntries` → `MemoEntry` | `.cascade`（注記の通り実効性なし） | `Book`側`@Relationship(deleteRule: .cascade)`＋`BookshelfViewModel.confirmDelete()`で明示的に`context.delete()` | FR-07（本単位削除） |
| `Book.conversationLogs` → `ConversationLog` | `.cascade`（注記の通り実効性なし） | `Book`側`@Relationship(deleteRule: .cascade)`＋`BookshelfViewModel.confirmDelete()`で明示的に`context.delete()` | FR-07（本単位削除） |
| `MemoEntry` ⇔ `ConversationLog`（同日） | リレーションシップなし（アプリケーションロジック） | `BookDetailViewModel.confirmDelete()` | FR-07（メモ単位削除） |

メモ単位削除時の同日`ConversationLog`連動削除は、モックコードの`BookDetailViewModel.confirmDelete()`が既にこの通りの実装（`Calendar.current.isDate($0.date, inSameDayAs: targetDate)`で同日ログを検索して削除、`book.cachedSummary`には触れない）になっている。本実装では`context.delete()`＋`context.save()`をこのロジックに追加するのみで、削除判定ロジック自体は変更不要。

```swift
// ViewModels/BookDetailViewModel.swift（本実装版・confirmDelete()の差分）
func confirmDelete(context: ModelContext) {
    guard let memo = memoPendingDeletion else { return }
    let targetDate = memo.date

    // 同一book・同一dateのConversationLogを明示的に検索して削除する（Book.cachedSummaryは保持）
    book.conversationLogs
        .filter { Calendar.current.isDate($0.date, inSameDayAs: targetDate) }
        .forEach { context.delete($0) }

    context.delete(memo)
    try? context.save()

    memoPendingDeletion = nil
    isShowingDeleteConfirmation = false
}
```

本単位削除（`BookshelfViewModel.confirmDelete()`）は、上記の理由によりSwiftDataの自動カスケードに頼らず、`memoEntries`・`conversationLogs`をそれぞれ明示的に削除してから`book`本体を削除する（`cachedSummary`は`Book`自体のプロパティのため`book`削除で消える。個別の削除処理は不要）。

```swift
// ViewModels/BookshelfViewModel.swift（本実装版・confirmDelete()の差分）
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
```

### 1-4. モックからの変更点（重要）

| 項目 | モックコード | 本実装 | 理由 |
|---|---|---|---|
| クラス修飾 | `@Observable final class` | `@Model final class` | SwiftData永続化のため |
| `MemoEntry.book`・`ConversationLog.book` | `weak var book: Book?` | `var book: Book?`（`weak`を外す） | **要確認事項ではなく確定事項**：SwiftDataの`@Model`プロパティに`weak`修飾子は使用できない（WebSearchで確認済み。SwiftDataはARCベースの参照カウントではなく永続化ストア側でグラフを管理するため、`weak`指定は不要かつコンパイルエラーの原因になる）。architecture.md 6.1のコード例も`weak`なしで統一されており、本実装はarchitecture.mdの記述通りに進めればよい |
| `id`フィールド | `let id: UUID` | `@Attribute(.unique) var id: UUID` | 一意制約をSwiftData側に持たせるため（`let`は`@Model`のプロパティ変更検知と相性が悪いため`var`にする） |
| `MemoEntry.adviceGenerationState` / `adviceDisplayState` | `@Observable`クラスの計算プロパティ・UI専用enumとして保持 | **モデルからは削除し、ViewModelまたはView側の状態として保持し直す** | `AdviceGenerationState`（`.generating`等）は永続化すべきでない一時的なUI状態であり、SwiftDataの`@Model`プロパティにできない（Equatableな`enum`で値を持つケース`.failed(AdviceFailureReason)`はCodable変換の手間が生じ、かつ「生成中」状態はアプリ再起動で消えるべき一時状態のため、そもそも永続化に向かない）。本実装では`MemoEditorViewModel`・`BookDetailViewModel`側が`[MemoEntry.id: AdviceGenerationState]`のような一時的な辞書、または各Viewが`@State`で保持する方式に置き換える（3-2参照） |
| `ConversationTurn` | `Identifiable`準拠（`id: UUID = UUID()`付き） | `Codable`のみ（`Identifiable`を外す） | `Identifiable`の`id`は「Gemini APIへ送信するJSONに紛れ込ませたくない一時的なUI用ID」であり、`Codable`とだけ組み合わせるとエンコード時に無関係な`id`フィールドが混入する。UI側（`ChatMessage`）で別途`id: UUID`を持たせれば`ForEach`の要件は満たせる（モックの`AIChatViewModel`は既に`ChatMessage`という別構造体でこれを行っており、`ConversationTurn.id`は実質使われていない） |
| `MockData.makeBooks()`等 | 全画面のシードデータ源 | 削除（1-5・3-3参照） | SwiftDataへの実永続化に伴い不要になる |

### 1-5. マイグレーション構成（`ModelContainer`初期化）

Prisma等のORMを使わないため、マイグレーションファイルは生成されない。SwiftDataは`Schema`に登録した`@Model`型からスキーマを自動生成する。Phase 1はスキーマ変更のリリースを想定しないため、`SchemaMigrationPlan`は不要（将来的にモデルにフィールド追加が必要になった場合はこの限りではなく、その時点で軽量マイグレーションの要否を再検討する）。

```swift
// MyBooksMemoApp.swift（本実装版）
import SwiftUI
import SwiftData

@main
struct MyBooksMemoApp: App {
    let modelContainer: ModelContainer

    init() {
        NavigationBarAppearanceConfigurator.configure()
        do {
            modelContainer = try ModelContainer(
                for: Schema([Book.self, MemoEntry.self, ConversationLog.self])
            )
        } catch {
            fatalError("ModelContainerの初期化に失敗しました: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            BookshelfView()
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
```

`ConversationTurn`は`@Model`ではなく`Codable`構造体のため`Schema`への個別登録は不要（`ConversationLog.turns`の属性として自動的に扱われる）。

**インデックスについて**：個人利用規模（想定データ量：本数十冊・メモ数百件程度）のため、`@Attribute(.index)`による明示的なインデックス最適化はPhase 1では行わない。`id`の一意制約（`@Attribute(.unique)`）のみで十分と判断する。将来的にデータ量が増えパフォーマンス上の問題が生じた場合は、`MemoEntry.date`・`ConversationLog.date`へのインデックス追加を検討する。

---

## 2. APIエンドポイント定義

> Cloudflare Workers（BFF）が`/chat`・`/summarize`・`/advice`の3エンドポイントを提供する。国立国会図書館サーチAPI（FR-01）はBFFを経由せずiOSアプリから直接呼び出すため、本セクションはこの3エンドポイントのみを対象とする（国立国会図書館サーチAPIの呼び出し仕様は2-4に別途まとめる）。

### 2-1. エンドポイント一覧

| FR | メソッド | パス | 概要 | 認証 | タイムアウト |
|---|---|---|---|---|---|
| FR-04 | POST | `/chat` | メモ内容・対話履歴からAIの次の質問を1件生成する | 要（`X-Shared-Secret`） | 15秒 |
| FR-05 | POST | `/summarize` | 全メモ・全対話ログから本単位の要約を1件生成する | 要（`X-Shared-Secret`） | 15秒 |
| FR-09 | POST | `/advice` | メモ内容（＋対話ログ）から今日のアドバイスを1件生成する | 要（`X-Shared-Secret`） | 15秒 |

全エンドポイント共通：`Content-Type: application/json`、レスポンスも`application/json`。`GET`等の他メソッドおよび未定義パスへのリクエストは`src/index.ts`が404を返す（architecture.md 5章）。

### 2-2. 共通仕様（認証・エラーフォーマット）

**認証フロー**（`lib/auth.ts`。FR-06共通ルールNo.6・NF-02）

```
1. リクエストヘッダー X-Shared-Secret の値を取得する
2. 環境変数 WORKERS_SHARED_SECRET と比較する
3. 不一致 or ヘッダー欠落 → Gemini APIを呼び出さずHTTP 401を返す
4. 一致 → 各routes/*.tsの処理に進む
```

**エラーレスポンスの統一フォーマット**

全エンドポイント・全異常系で以下の形式に統一する。

```json
{
  "error": "unauthorized" | "invalid_request" | "rate_limited" | "generation_failed",
  "message": "サーバー側のログ・デバッグ用の説明文（iOS側はこの値を画面表示に使わない）"
}
```

| HTTPステータス | `error`値 | 発生条件 | 対応するiOS側`APIError` |
|---|---|---|---|
| 400 | `invalid_request` | `lib/validate.ts`のリクエストボディ検証失敗（必須フィールド欠落・型不一致） | `.decodingError`相当（4-1参照） |
| 401 | `unauthorized` | `X-Shared-Secret`不一致（FR-06共通ルールNo.6） | `.unauthorized` |
| 429 | `rate_limited` | Gemini API側の429を透過 | `.rateLimited` |
| 500 | `generation_failed` | Gemini API呼び出し失敗・タイムアウト・レスポンス形式異常（NF-03：空文字・極端に長い等） | `.serverError` |

> NF-04「HTTPステータスコード・スタックトレース等の技術的情報は画面に表示しない」に従い、iOS側は`error`・`message`の値をそのまま画面に出さず、HTTPステータスコードから`APIError`（4-1）に変換した上で、各FR・各画面の異常系メッセージ（basic_design.md Section 7 ERR-09〜17）に一律マッピングする。`message`はXcodeコンソールログにのみ出力してよい（FR-06共通ルールNo.5。ただしメモ本文・対話内容そのものは含めない）。

### 2-3. 各エンドポイントの詳細

---

#### FR-04：`POST /chat`

**認証**：要（`X-Shared-Secret`）
**呼び出し元**：`CloudflareWorkersClient.chat(bookTitle:memoContent:conversationHistory:)`（`AIChatViewModel`から、往復のたびに呼ばれる）

**リクエスト**

```typescript
body: {
  bookTitle: string            // 必須。空文字は不可
  memoContent: string          // 必須。MemoEntry.contentItemsを改行連結した文字列。空文字は不可
  conversationHistory: {       // 必須。初回は空配列
    question: string
    answer: string
  }[]
}
```

**レスポンス**

```typescript
// 成功：HTTP 200
{
  question: string   // AIの次の質問テキスト1件
}

// エラー：HTTP 400 / 401 / 429 / 500（2-2の共通フォーマット）
{
  error: "invalid_request" | "unauthorized" | "rate_limited" | "generation_failed",
  message: string
}
```

**実装上の注意**
- `bookTitle`・`memoContent`が空文字の場合は`invalid_request`（400）を返す。`conversationHistory`は配列である限り要素0件を許容する（初回リクエストのため）
- Gemini APIへのプロンプトは「メモ内容＋これまでの往復履歴」を渡し、言語化・具体性向上を目的とした質問文を1件だけ生成させる（往復5回制限・終了判定はiOS側のロジックであり、Workers側は往復回数を関知しない。requirements.md FR-04 Step5参照）
- レスポンスがプレーンテキストではなくJSON形式で返ってこない、または`question`が空文字の場合はNF-03の異常形式としてWorkers側で500に変換する

---

#### FR-05：`POST /summarize`

**認証**：要（`X-Shared-Secret`）
**呼び出し元**：`CloudflareWorkersClient.summarize(bookTitle:memos:conversationLogs:)`（`SummaryViewModel.generateSummary()`から、ボタンタップ時のみ呼ばれる）

**リクエスト**

```typescript
body: {
  bookTitle: string             // 必須。空文字は不可
  memos: {                      // 必須。1件以上（0件の場合はiOS側がボタンを非活性にしているため到達しない想定だが、Workers側でも0件チェックは行う）
    date: string                 // "yyyy-MM-dd"形式
    content: string              // MemoEntry.contentItemsを改行連結した文字列
  }[]
  conversationLogs: {            // 必須（対話ログがない場合は空配列）
    date: string
    turns: { question: string; answer: string }[]
  }[]
}
```

**レスポンス**

```typescript
// 成功：HTTP 200
{
  summary: string   // 要約テキスト1件
}

// エラー：HTTP 400 / 401 / 429 / 500（2-2の共通フォーマット）
{
  error: "invalid_request" | "unauthorized" | "rate_limited" | "generation_failed",
  message: string
}
```

**実装上の注意**
- `memos`が空配列の場合は`invalid_request`（400）を返す（iOS側は`SummaryViewModel.canGenerate`でメモ0件時にボタンを非活性にしているため通常到達しないが、Workers側は単独でも防御的に検証する）
- 成功時、iOS側は`summary`の値を`Book.cachedSummary`に、レスポンス受信時刻を`Book.cachedSummaryGeneratedAt`に保存する（requirements.md FR-05 Step7）
- 失敗時、`Book.cachedSummary`・`cachedSummaryGeneratedAt`は変更しない（既存キャッシュの表示を維持する。requirements.md FR-05異常系）

---

#### FR-09：`POST /advice`

**認証**：要（`X-Shared-Secret`）
**呼び出し元**：`CloudflareWorkersClient.generateAdvice(bookTitle:memoContent:conversationTurns:)`（`MemoEditorViewModel`のDLG-04「いいえ」選択時、または`AIChatViewModel`の対話終了時にバックグラウンドで呼ばれる。画面遷移をブロックしないFire-and-forget呼び出し）

**リクエスト**

```typescript
body: {
  bookTitle: string                // 必須。空文字は不可
  memoContent: string              // 必須。MemoEntry.contentItemsを改行連結した文字列。空文字は不可
  conversationTurns: {             // 必須（対話を実施していない、または1ターンも成立しなかった場合は空配列）
    question: string
    answer: string
  }[]
}
```

**レスポンス**

```typescript
// 成功：HTTP 200
{
  advice: string   // アドバイステキスト1件
}

// エラー：HTTP 400 / 401 / 429 / 500（2-2の共通フォーマット）
{
  error: "invalid_request" | "unauthorized" | "rate_limited" | "generation_failed",
  message: string
}
```

**実装上の注意**
- 呼び出し元はレスポンスを`await`で待たずFire-and-forget的に呼ぶ（architecture.md 4章の`CloudflareWorkersClient`責務欄参照）。iOS側は生成中・生成成功・生成失敗の状態を`MemoEntry.dailyAdvice`の値の有無＋一時的なUI状態（1-4参照）で管理する
- 成功時：`dailyAdvice`にレスポンステキストを保存する
- 失敗時：`dailyAdvice`は`nil`のまま。エラー種別（API失敗/オフライン/レート制限）に応じてERR-15〜17（basic_design.md Section 7）を付箋内に表示する。ただしオフライン判定（ERR-16）はWorkersへのリクエスト自体を送らず、iOS側のネットワーク到達性チェック（2-4末尾のAPIClient設計参照）の時点で判定する

### 2-4. 国立国会図書館サーチAPI（FR-01・参考。Workers非経由）

BFFを経由せずiOSアプリから直接呼び出す（NF-02：認証不要のため）。

```
GET https://ndlsearch.ndl.go.jp/api/sru?operation=searchRetrieve&query=isbn%3D{ISBN}&recordSchema=dcndl&recordPacking=xml
タイムアウト：10秒
認証：不要
```

レスポンスはdcndl形式のXML。`dc:title`（タイトル）・`dc:creator`（著者）はDublin Coreの標準要素であり、この2項目の抽出方法は確定情報として扱ってよい。

> ⚠️ **要確認事項（architecture.mdから引き継ぎ・未解決）**：書影（表紙画像）の取得方法について、WebSearchで追加調査した結果、次の2点が判明した。
> 1. 国立国会図書館サーチには`https://ndlsearch.ndl.go.jp/thumbnail/{識別子}.jpg`という書影専用のAPIが別途存在する（SRU検索結果のXMLに画像バイナリやURLが直接含まれるわけではない）
> 2. `{識別子}`にISBNをそのまま渡しても取得できない事例が複数報告されており、レスポンスXML内の`rdfs:seeAlso`要素等から抽出できる「JP-eコード」（20桁の英数字）を使う必要がある場合がある。ただしJP-eコードを安定的に取得する一般的な方法は確立されておらず、確実に書影が取得できる保証はない
>
> この事実は、architecture.mdが「Phase 5作成前またはFR-01実装着手前に確定させる必要がある」と明記していた要確認事項に対する調査結果であり、まだ完全には解消していない。**Phase 7でFR-01（NDLSearchService）に着手する前に、実際のISBN（例：ダミーデータの`9784478025819`）でSRU APIとサムネイルAPIの両方を実機/実環境で叩き、書影が実際に取得できるか・取得できる場合のURLパターンを確認するpre-implementation-checkを行うこと**。取得できないと判明した場合でも、requirements.md「作らないこと」に明記の通りAmazon等への代替フォールバックは行わず、プレースホルダー画像表示（`BookCoverView`の書影なし描画。モックで実装済み）にフォールバックすればよいため、機能要件自体への影響はない。

---

## 3. コンポーネント構成

### 3-1. iOSディレクトリ構成（Phase 7時点）

architecture.md 4章のディレクトリ構成をベースに、モックからの変更要否を注記する。

```
MyBooksMemo/
├── MyBooksMemoApp.swift                     # 【変更】ModelContainer初期化を追加（1-5参照）
├── Models/
│   ├── Book.swift                           # 【変更】@Model化、1-1参照
│   ├── MemoEntry.swift                      # 【変更】@Model化、UI専用状態(adviceGenerationState等)を除去
│   └── ConversationLog.swift                # 【変更】@Model化、ConversationTurnからIdentifiable除去
├── Views/
│   ├── Bookshelf/
│   │   ├── BookshelfView.swift              # 【変更】@Query／ModelContext経由の取得・削除に置き換え
│   │   └── BookCardView.swift               # 【流用】UIロジックは変更不要
│   ├── BookRegistration/
│   │   ├── BarcodeScannerView.swift         # 【変更】実DataScannerViewController統合、モック要素除去（3-4参照）
│   │   ├── ManualEntryFormView.swift        # 【流用】PhotosPicker処理は変更不要。保存先がModelContextになる点のみ変更
│   │   └── BookConfirmationView.swift       # 【流用】UIロジックは変更不要
│   ├── BookDetail/
│   │   ├── BookDetailView.swift             # 【流用】UIロジックは変更不要
│   │   ├── MemoListView.swift               # 【流用】UIロジックは変更不要
│   │   ├── MemoEditorView.swift             # 【変更】保存処理をModelContext経由に、アドバイス生成トリガーを実API呼び出しに置き換え
│   │   └── SummaryView.swift                # 【変更・追加】要約生成を実API呼び出しに。ERR-12/13/14のエラー表示UIを新規追加（現モックには存在しない）
│   └── AIChat/
│       └── AIChatView.swift                 # 【変更】固定質問リストを実/chat呼び出しに、モック用エラープレビューUIを除去
├── ViewModels/
│   ├── BookshelfViewModel.swift             # 【変更】in-memory配列 → ModelContext
│   ├── BookRegistrationViewModel.swift      # 【変更】ScanPreviewStateを実状態（権限・NDL結果）に置き換え
│   ├── ManualEntryFormViewModel.swift       # 【流用】バリデーションロジックは変更不要
│   ├── BookDetailViewModel.swift            # 【変更】confirmDelete()にModelContext操作を追加（1-3参照）
│   ├── MemoEditorViewModel.swift            # 【変更】save()の保存先をModelContext経由に、CloudflareWorkersClient呼び出しを追加
│   ├── AIChatViewModel.swift                # 【変更】固定質問→実/chat呼び出し、ConversationLog保存をModelContext経由に
│   └── SummaryViewModel.swift               # 【変更・追加】実/summarize呼び出し、エラー状態プロパティを新規追加
├── Services/                                # 【新規ディレクトリ】
│   ├── APIClient.swift                      # 【新規】共通通信ラッパー（3-3参照）
│   ├── NDLSearchService.swift               # 【新規】NDL SRU API呼び出し・XMLパース
│   └── CloudflareWorkersClient.swift        # 【新規】/chat・/summarize・/advice呼び出し
├── Utilities/
│   ├── Config.swift                         # 【新規】Info.plist経由の環境変数読み取り（architecture.md 8.3）
│   ├── APIError.swift                       # 【新規】共通エラー型（4-1参照）
│   ├── BookDraft.swift                      # 【流用】変更不要
│   ├── BookCoverView.swift                  # 【流用】変更不要
│   ├── GridPaperBackground.swift            # 【流用】変更不要（UI装飾のみ）
│   ├── NotebookTexture.swift                # 【流用】変更不要（UI装飾のみ）
│   ├── NavigationBarAppearanceConfigurator.swift # 【流用】変更不要
│   ├── Theme.swift                          # 【流用】変更不要
│   └── MockData.swift                       # 【削除】3-4参照
├── Resources/
│   └── Assets.xcassets
└── Info.plist                               # 【変更】NSCameraUsageDescription・CloudflareWorkersURL・WorkersSharedSecretキーを追加（architecture.md 8.3）
```

### 3-2. 主要ViewModelの変更内容（詳細）

**`BookshelfViewModel`**

```swift
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

    func addBook(_ book: Book) {
        context.insert(book)
        try? context.save()
        fetchBooks()
    }

    func requestDelete(_ book: Book) {
        bookPendingDeletion = book
        isShowingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let book = bookPendingDeletion else { return }
        context.delete(book)   // @Relationship(deleteRule: .cascade)がmemoEntries・conversationLogsを自動削除
        try? context.save()
        bookPendingDeletion = nil
        isShowingDeleteConfirmation = false
        fetchBooks()
    }

    func cancelDelete() {
        bookPendingDeletion = nil
        isShowingDeleteConfirmation = false
    }
}
```

> `BookshelfView`から`@Environment(\.modelContext)`を取得して`BookshelfViewModel(context:)`に渡す（またはView側で`@Query private var books: [Book]`を直接使い、ViewModelを削除・簡略化する設計に変更してもよい。どちらもMVVMの原則を大きく外れないため、実装時にClaude Codeの判断で選んでよい。ただし選んだ場合はBookDetailView等の他画面のパターンとも一貫性を持たせること）

**`SummaryViewModel`（エラー状態の新規追加）**

現行モックにはFR-05のエラー状態（ERR-12〜14）を表現するプロパティが一切存在しない（`SummaryView`にもエラー表示UIがない）。`AIChatViewModel`の`ChatPreviewError`、`MemoEntry`の`AdviceFailureReason`と同様のパターンで、本実装時に新規追加する。

```swift
enum SummaryFailureReason: Equatable {
    case apiFailure   // ERR-12
    case offline      // ERR-13
    case rateLimited  // ERR-14

    var message: String {
        switch self {
        case .apiFailure: return "要約の生成に失敗しました"
        case .offline: return "インターネットに接続されていないため要約を作成できません"
        case .rateLimited: return "本日の要約生成の利用上限に達しました"
        }
    }
}

@Observable
final class SummaryViewModel {
    let book: Book
    var isGenerating = false
    var failureReason: SummaryFailureReason?   // 【新規】nilの間はエラー表示なし

    // ...buttonLabel／canGenerate／generatedAtTextは変更不要...

    func generateSummary() async {
        guard canGenerate, !isGenerating else { return }
        failureReason = nil
        isGenerating = true
        defer { isGenerating = false }

        guard NetworkReachability.isConnected else {
            failureReason = .offline
            return
        }
        do {
            let response = try await CloudflareWorkersClient.shared.summarize(
                bookTitle: book.title,
                memos: book.memoEntries.map { .init(date: $0.date, content: $0.joinedContentForAI) },
                conversationLogs: book.conversationLogs.map { .init(date: $0.date, turns: $0.turns) }
            )
            book.cachedSummary = response.summary
            book.cachedSummaryGeneratedAt = .now
        } catch let error as APIError {
            failureReason = error.summaryFailureReason   // APIError → SummaryFailureReasonへのマッピング（4-1参照）
        } catch {
            failureReason = .apiFailure
        }
    }
}
```

`SummaryView`側にも、`MemoCardView`のアドバイス失敗表示と同様の要領で、`failureReason`が非nilのときにエラーメッセージ＋（無料枠超過以外は）「再試行」ボタンを表示するUIを追加する。

**`MemoEntry`のアドバイス生成状態管理（永続モデルからの分離）**

1-4の通り`adviceGenerationState`はモデルに持たせられないため、生成中・失敗状態は`BookDetailViewModel`が`[UUID: AdviceGenerationState]`（`MemoEntry.id`をキーにした辞書）として一時的に保持する形に変更する。

```swift
// ViewModels/BookDetailViewModel.swift に追加
enum AdviceGenerationState: Equatable {
    case idle, generating, failed(AdviceFailureReason)
}

@Observable
final class BookDetailViewModel {
    // ...既存プロパティ...
    private var adviceStates: [UUID: AdviceGenerationState] = [:]

    func adviceDisplayState(for memo: MemoEntry) -> AdviceDisplayState {
        if let advice = memo.dailyAdvice { return .success(advice) }
        switch adviceStates[memo.id] ?? .idle {
        case .idle: return .notTriggered
        case .generating: return .generating
        case .failed(let reason): return .failed(reason)
        }
    }

    func triggerAdviceGeneration(for memo: MemoEntry) {
        guard adviceStates[memo.id] != .generating else { return }
        adviceStates[memo.id] = .generating
        Task {
            guard NetworkReachability.isConnected else {
                await MainActor.run { adviceStates[memo.id] = .failed(.offline) }
                return
            }
            do {
                let response = try await CloudflareWorkersClient.shared.generateAdvice(
                    bookTitle: memo.book?.title ?? "",
                    memoContent: memo.joinedContentForAI,
                    conversationTurns: /* 対話ログがあれば渡す。3-2 MemoEditorViewModel/AIChatViewModel参照 */ []
                )
                await MainActor.run {
                    memo.dailyAdvice = response.advice
                    adviceStates[memo.id] = .idle
                }
            } catch let error as APIError {
                await MainActor.run { adviceStates[memo.id] = error.adviceFailureReason.map { .failed($0) } ?? .failed(.apiFailure) }
            } catch {
                await MainActor.run { adviceStates[memo.id] = .failed(.apiFailure) }
            }
        }
    }
}
```

`AdviceDisplayState`・`AdviceFailureReason`（モックの`MemoEntry.swift`に定義済み）はそのまま流用してよいが、定義場所を`MemoEntry.swift`から`BookDetailViewModel.swift`（またはUtilities配下の独立ファイル）に移動する。

**`MemoEditorViewModel`・`AIChatViewModel`**：`triggerAdviceGeneration()`の呼び出し元を`memo.triggerAdviceGeneration()`（モデルメソッド）から`bookDetailViewModel.triggerAdviceGeneration(for: memo)`（ViewModelメソッド）に置き換える。`AIChatViewModel`の`send()`内の固定質問取得（`askNextQuestion()`）を、`CloudflareWorkersClient.chat()`への実呼び出しに置き換える。往復上限（5回）・「終了する」ボタンによる終了判定ロジック自体（`endConversation()`・`finishAfterLimitReached()`・`saveIfNeeded()`）は変更不要。

### 3-3. Cloudflare Workersのモジュール構成

architecture.md 5章の構成をそのまま採用する（Phase 3ではWorkers側は未着手のため、Phase 7が新規実装）。

```
workers/
├── src/
│   ├── index.ts        # pathnameで/chat・/summarize・/adviceに振り分け。他は404
│   ├── routes/
│   │   ├── chat.ts       # validate → 認証(lib/auth) → プロンプト構築 → lib/gemini呼び出し → { question } を返す
│   │   ├── summarize.ts  # validate → 認証 → プロンプト構築 → lib/gemini呼び出し → { summary } を返す
│   │   └── advice.ts     # validate → 認証 → プロンプト構築 → lib/gemini呼び出し → { advice } を返す
│   ├── lib/
│   │   ├── auth.ts        # X-Shared-Secret検証。不一致時は401のErrorResponseを返す
│   │   ├── gemini.ts       # gemini-3.1-flash-lite への fetch 呼び出し。レスポンス空文字チェック（NF-03）
│   │   └── validate.ts     # ChatRequest/SummarizeRequest/AdviceRequestの型ガード関数
│   └── types.ts          # 4-2参照
├── wrangler.jsonc
├── package.json
├── tsconfig.json
└── .dev.vars
```

**各routes/*.tsの処理順序（共通パターン）**

```
1. リクエストボディをJSONとしてパースする（パース失敗 → invalid_request, 400）
2. lib/validate.tsの型ガード関数でリクエスト形式を検証する（不正 → invalid_request, 400）
3. lib/auth.tsでX-Shared-Secretを検証する（不一致 → unauthorized, 401）
4. プロンプトを構築し、lib/gemini.tsを呼び出す
   - Gemini APIが429を返す → rate_limited, 429を透過
   - Gemini APIがタイムアウト・5xx・空文字/異常形式のレスポンスを返す → generation_failed, 500
5. 成功時、該当エンドポイントのレスポンス形式（2-3参照）でJSONを返す
```

> Step2（バリデーション）とStep3（認証）の順序：不正なリクエストボディでも認証だけ先に通す設計と、認証前にリクエスト内容を検査する設計のどちらもあり得るが、本設計では「不正な形式のリクエストは認証結果によらず一律400を返す」方式（Step2を先に実施）を採用する。理由：シークレットを知らない第三者に対しても、リクエスト形式に関する情報（どのフィールドが必須か等）を401より先に返してしまう trade-off はあるが、エンドポイントが3つしかなく個人開発規模のため実害は小さく、実装の単純さを優先する。認証を先に行う方式に変更したい場合は実装時の判断でよい（要件・エラー文言の変更を伴わないため要確認事項とはしない）。

### 3-4. モック→本実装の引き継ぎ方針：モック専用表記の除去リスト

> **重要**：本アプリはWeb UIではないため`<title>`タグは存在しないが、同種の「モック専用であることが分かる表記・要素」がSwiftUIのラベル文言・専用UI・専用コード（enum／メソッド）として複数箇所に存在する。以下は本実装完了時点で**必ず取り除く**、またはPhase 7実装時に置き換える対象である。basic_design.mdが「モックで実装しないこと」として指定した項目の裏返しであり、除去し忘れるとApp Store配布時等にモック確認用のUIがユーザーに見えてしまう。

| # | ファイル | 除去・置き換え対象 | 置き換え後 |
|---|---|---|---|
| 1 | `Utilities/MockData.swift` | ファイル全体 | 削除。`makeBooks()`が担っていたシードデータ投入は不要になる（SwiftDataは空の状態から開始する）。`#Preview`用に最小限のシードを残したい場合は`PreviewData.swift`等の別名にし、本体コード（View/ViewModel）から一切参照されない状態にする |
| 2 | `ViewModels/BookRegistrationViewModel.swift` | `ScanPreviewState`列挙型、`simulateDetection()`メソッド | 削除。実際のカメラ権限判定結果・`NDLSearchService`の呼び出し結果に応じた状態（`.scanning`/`.permissionDenied`/エラー種別）をリアルタイムに算出するロジックに置き換える |
| 3 | `Views/BookRegistration/BarcodeScannerView.swift` | 「（モック用）バーコードを検出したことにする」ボタン、`previewStateSelector`（`Picker`）とラベル「モック確認用：状態プレビュー（本実装では削除）」 | 削除。カメラプレビュー領域を実際の`DataScannerViewController`（`UIViewControllerRepresentable`）に置き換える |
| 4 | `ViewModels/AIChatViewModel.swift` | `ChatPreviewError`列挙型、`cyclePreviewError()`・`retryAfterError()`（プレビュー切替専用ロジック） | 削除。実際の`CloudflareWorkersClient.chat()`呼び出しの成功/失敗結果に応じたエラー状態管理に置き換える |
| 5 | `Views/AIChat/AIChatView.swift` | `debugErrorPreviewControl`（「モック確認用：エラー表示を切替」ボタン） | 削除 |
| 6 | `Models/MemoEntry.swift` | `triggerAdviceGeneration()`内の`Task.sleep`＋`MockData.fixedDailyAdviceText`固定セット | 削除（メソッド自体を`BookDetailViewModel`に移動。3-2参照） |
| 7 | `ViewModels/SummaryViewModel.swift` | `generateSummary()`内の`Task.sleep`＋`MockData.fixedSummaryText`固定セット | 削除。実際の`CloudflareWorkersClient.summarize()`呼び出しに置き換える |
| 8 | 各View（`BookshelfView`・`BookCardView`・`BookDetailView`・`MemoListView`・`MemoCardView`・`ManualEntryFormView`・`AIChatView`）の`#Preview`ブロック | `MockData.makeBooks()`を参照している箇所 | `MockData.swift`削除に伴い、in-memoryな`ModelContainer(for: ..., configurations: .init(isStoredInMemoryOnly: true))`を使うプレビュー方式、または`PreviewData`の最小シード関数に置き換える |

> なお、basic_design.md Section 0が定める「モックで実装しないこと」のうち、**ダークモード非対応**（`preferredColorScheme(.light)`固定）は引き続き有効な仕様（ユーザー確定事項）であり、除去対象ではない。

---

## 4. 型定義・バリデーションスキーマ

### 4-1. Swift側：共通エラー型・リクエスト/レスポンス型

```swift
// Utilities/APIError.swift
import Foundation

/// FR-06共通ルールNo.4（エラーメッセージのトーン統一）に対応する共通エラー型。
/// 各ViewModelはこの型を受け取り、FR固有の文言（ERR-09〜17）にマッピングする。
enum APIError: Error {
    case timeout          // URLSessionのタイムアウト（10秒/15秒超過）
    case network          // ネットワーク接続なし（NWPathMonitorで事前判定 or URLError.notConnectedToInternet）
    case unauthorized      // HTTP 401（X-Shared-Secret不一致）
    case rateLimited       // HTTP 429
    case serverError       // HTTP 500（Gemini呼び出し失敗・タイムアウト・NF-03のレスポンス形式異常）
    case decodingError     // HTTP 400、またはレスポンスJSONのデコード失敗
}

extension APIError {
    /// FR-04（AIChatViewModel）向けマッピング
    var chatFailureReason: ChatPreviewError? {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
    /// FR-05（SummaryViewModel）向けマッピング
    var summaryFailureReason: SummaryFailureReason {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
    /// FR-09（BookDetailViewModel）向けマッピング
    var adviceFailureReason: AdviceFailureReason {
        switch self {
        case .network: return .offline
        case .rateLimited: return .rateLimited
        case .timeout, .serverError, .unauthorized, .decodingError: return .apiFailure
        }
    }
}
```

```swift
// Services/CloudflareWorkersClient.swift 内のリクエスト/レスポンス型
struct ChatRequest: Codable {
    let bookTitle: String
    let memoContent: String
    let conversationHistory: [ConversationTurn]
}
struct ChatResponse: Codable {
    let question: String
}

struct MemoSummaryInput: Codable {
    let date: String     // ISO8601日付文字列（"yyyy-MM-dd"）
    let content: String
}
struct ConversationLogSummaryInput: Codable {
    let date: String
    let turns: [ConversationTurn]
}
struct SummarizeRequest: Codable {
    let bookTitle: String
    let memos: [MemoSummaryInput]
    let conversationLogs: [ConversationLogSummaryInput]
}
struct SummarizeResponse: Codable {
    let summary: String
}

struct AdviceRequest: Codable {
    let bookTitle: String
    let memoContent: String
    let conversationTurns: [ConversationTurn]
}
struct AdviceResponse: Codable {
    let advice: String
}

/// Workers側のエラーレスポンス（2-2参照）。iOS側はHTTPステータスコードで判定するため
/// この型自体をUI表示に使うことはないが、Xcodeコンソールログ出力（FR-06 No.5）には使う
struct WorkersErrorResponse: Codable {
    let error: String
    let message: String?
}
```

`date`フィールドを`Date`型ではなく`String`（`"yyyy-MM-dd"`）で送る理由：Gemini APIへのプロンプトに人間可読な日付文字列として渡したいため、`ISO8601DateFormatter`ではなく単純な年月日文字列に統一する。iOS側で`DateFormatter`（`dateFormat = "yyyy-MM-dd"`）を使い変換する。

### 4-2. TypeScript側：`workers/src/types.ts`

```typescript
export interface ConversationTurn {
  question: string;
  answer: string;
}

export interface ChatRequest {
  bookTitle: string;
  memoContent: string;
  conversationHistory: ConversationTurn[];
}
export interface ChatResponse {
  question: string;
}

export interface MemoSummaryInput {
  date: string;
  content: string;
}
export interface ConversationLogSummaryInput {
  date: string;
  turns: ConversationTurn[];
}
export interface SummarizeRequest {
  bookTitle: string;
  memos: MemoSummaryInput[];
  conversationLogs: ConversationLogSummaryInput[];
}
export interface SummarizeResponse {
  summary: string;
}

export interface AdviceRequest {
  bookTitle: string;
  memoContent: string;
  conversationTurns: ConversationTurn[];
}
export interface AdviceResponse {
  advice: string;
}

export type ErrorCode = "invalid_request" | "unauthorized" | "rate_limited" | "generation_failed";

export interface ErrorResponse {
  error: ErrorCode;
  message?: string;
}
```

### 4-3. TypeScript側：`workers/src/lib/validate.ts`（型ガード関数）

architecture.mdの方針（1.2）に従い、zod等は導入せず手書きの型ガード関数とする。

```typescript
function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isConversationTurn(value: unknown): value is ConversationTurn {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return typeof v.question === "string" && typeof v.answer === "string";
}

export function isChatRequest(body: unknown): body is ChatRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  return (
    isNonEmptyString(v.bookTitle) &&
    isNonEmptyString(v.memoContent) &&
    Array.isArray(v.conversationHistory) &&
    v.conversationHistory.every(isConversationTurn)
  );
}

export function isSummarizeRequest(body: unknown): body is SummarizeRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  const memosValid =
    Array.isArray(v.memos) &&
    v.memos.length > 0 &&
    v.memos.every(
      (m) =>
        typeof m === "object" && m !== null &&
        isNonEmptyString((m as Record<string, unknown>).date) &&
        typeof (m as Record<string, unknown>).content === "string"
    );
  const logsValid =
    Array.isArray(v.conversationLogs) &&
    v.conversationLogs.every(
      (l) =>
        typeof l === "object" && l !== null &&
        isNonEmptyString((l as Record<string, unknown>).date) &&
        Array.isArray((l as Record<string, unknown>).turns) &&
        (l as { turns: unknown[] }).turns.every(isConversationTurn)
    );
  return isNonEmptyString(v.bookTitle) && memosValid && logsValid;
}

export function isAdviceRequest(body: unknown): body is AdviceRequest {
  if (typeof body !== "object" || body === null) return false;
  const v = body as Record<string, unknown>;
  return (
    isNonEmptyString(v.bookTitle) &&
    isNonEmptyString(v.memoContent) &&
    Array.isArray(v.conversationTurns) &&
    v.conversationTurns.every(isConversationTurn)
  );
}
```

> `memos`は「1件以上」を必須とする（`isSummarizeRequest`が`v.memos.length > 0`を検証する）。`conversationLogs`・`conversationHistory`・`conversationTurns`は0件を許容する（配列であることのみ検証する）。

### 4-4. バリデーションルール一覧（Swift側・クライアントサイド）

モックコードに既に実装済みのバリデーションロジックをそのまま踏襲する（変更不要）。

| 対象 | ルール | 実装箇所（モック済み・変更不要） | 対応ERR |
|---|---|---|---|
| `title`（FR-02） | `trimmingCharacters(in: .whitespacesAndNewlines)`後に空文字なら不可 | `ManualEntryFormViewModel.validate()` | ERR-06 |
| `author`（FR-02） | 未入力時は`"著者不明"`を自動代入（バリデーションエラーにはしない） | `RegistrationFlowView.complete(with:)` | — |
| `contentItems`（FR-03） | 各要素を`trimmingCharacters(in: .whitespacesAndNewlines)`後、空文字要素を除外。除外後1件も残らなければ不可 | `MemoEditorViewModel.validate()`／`save()` | ERR-08 |

いずれも「保存直前にクライアント側で検証する」という設計であり、Workers側では対応するバリデーションを行わない（メモ・書籍登録はSwiftDataのみで完結しWorkersを経由しないため）。

### 4-5. NF-03（Gemini応答形式異常）の扱い

`lib/gemini.ts`はGemini APIからのレスポンステキストが以下のいずれかに該当する場合、呼び出し元のroutes/*.tsに例外を投げ、routes側が`generation_failed`（500）に変換する。

- レスポンステキストが空文字、または空白のみ
- レスポンスがJSON形式で返る想定はない（NF-03「プレーンテキストとして扱い、JSON形式のレスポンスは期待しない」）ため、Gemini APIからのテキストをそのまま`question`/`summary`/`advice`の値として使う。パース処理自体は発生しない

「極端に長い」の具体的な文字数閾値はrequirements.md・basic_design.mdのいずれにも数値の指定がない。Phase 1では上限チェックを実装せず、実運用で問題が生じた場合にのみ対処する（要確認事項とはしない軽微な事項と判断。個人開発の同期的な使い方であり、極端に長い応答が生成される具体的なリスクシナリオが現時点でないため）。

---

## 要確認事項

1. **NDL API書影取得方式（2-4参照、architecture.mdからの引き継ぎ）**：SRU APIのXMLレスポンスとは別に書影専用API（`https://ndlsearch.ndl.go.jp/thumbnail/{識別子}.jpg`）が存在すること、ISBNをそのまま渡しても取得できない場合がありJP-eコード抽出が必要になりうることがWebSearchで判明した。Phase 7のFR-01実装着手前に、実際のISBN（ダミーデータの`9784478025819`等）で両APIを実機/実環境から呼び出し、書影取得の可否・具体的なURLパターンを確認するpre-implementation-checkが必要。取得不可と判明した場合もプレースホルダー画像へのフォールバックで機能要件は満たせるため、機能停止には至らない。

2. **バリデーション先行順序（3-3参照）**：Workers側の各routes/*.tsで「リクエスト形式検証→シークレット認証」の順に実施する設計としたが、「シークレット認証→リクエスト形式検証」の順にする代替案もある。エラー文言・ステータスコードの一覧に影響はないため実装時の判断に委ねてよいと判断したが、念のため要確認事項として記載する。

3. **`BookshelfViewModel`の`@Query`化について（3-2参照）**：ViewModelが`ModelContext`を手動で保持し`fetch()`を呼ぶ設計と、View側で`@Query`プロパティラッパーを直接使いViewModelを薄くする設計のどちらもあり得る。本ドキュメントは前者（既存のBookshelfViewModelの構造を維持しやすい）で記述したが、SwiftUI標準の`@Query`を使う方がコード量が少なく一般的なパターンでもあるため、実装時にどちらを採用するかはClaude Codeの判断に委ねてよい。
