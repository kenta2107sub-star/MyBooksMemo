# アーキテクチャ設計書

> **プロジェクト名**：MyBooksMemo（読書メモ・言語化トレーニングアプリ）
> **対象フェーズ**：Phase 1（MVP）のみ
> **このドキュメントの用途**：Claude Codeでの実装に使用する。技術スタック・システム構成・ディレクトリ構成・環境変数を記載している。
> **関連ドキュメント**：
> - `MyBooksMemo_requirements.md`（機能要件・非機能要件）
> - `MyBooksMemo_setup.md`（開発着手前チェックリスト・各種設定手順 ※このファイルの後に作成。環境変数一覧をチェックリストAに転記する）
> - `MyBooksMemo_basic_design.md`（画面仕様・モック実装指示 ※このファイルの後に作成。技術スタック・ディレクトリ構成をSection 0に転記する）

---

## 1. 技術スタック

本アプリは「iOSアプリ（クライアント）」と「Cloudflare Workers（BFF）」の2プロジェクト構成。それぞれの技術選定を分けて記載する。

### 1.1 iOSアプリ

| カテゴリ | 採用技術 | 選定理由 |
|---|---|---|
| 言語 | Swift 5.9系（Xcode 15.2同梱） | 現在の開発環境（Xcode 15.2 / iOS SDK 17.2）がサポートする最新のSwift。SwiftDataの利用に必須 |
| UIフレームワーク | SwiftUI | requirements.mdでネイティブUI前提が確定済み。宣言的UIによりMVVMのView/ViewModel分離がしやすい |
| アーキテクチャパターン | MVVM | ユーザー確定事項。View（SwiftUI）・ViewModel（`@Observable`または`ObservableObject`）・Model（SwiftData `@Model`）の3層分離 |
| 最小対応OS | iOS 17.0 | SwiftDataの動作要件（iOS 17+）。かつ現在の開発環境（Xcode 15.2 / iOS SDK 17.2）でビルド可能な上限に合わせた、ユーザー確定事項 |
| ローカル永続化 | SwiftData | ユーザー確定事項。iOS 17ネイティブのCore Dataベース永続化フレームワークで、外部ライブラリ（Realm等）を追加せずに要件（3モデル・カスケード削除）を満たせる |
| バーコードスキャン | VisionKit `DataScannerViewController` | requirements.md FR-01で確定済み。カメラ映像からのリアルタイムバーコード検出をUIKit標準APIのみで実現できる（iOS 16+対応、最小対応OS17を満たす） |
| 画像選択（手入力時） | PhotosUI `PhotosPicker` | FR-02の表紙画像選択に使用。SwiftUI標準統合されたAPIで外部ライブラリ不要 |
| 通信 | `URLSession`（async/await） | 外部通信先が2種類（NDL API直叩き・Cloudflare Workers経由）のみで、リクエスト数も少量（1日5〜15件程度）。Alamofire等の追加は過剰と判断し標準フレームワークで完結させる |
| JSON変換 | `Codable` | Cloudflare Workersとの通信ペイロードの型安全なエンコード/デコードに使用。外部ライブラリ不要 |
| 依存管理 | Swift Package Manager（SPM） | Xcode標準。**Phase 1では外部パッケージの追加は不要**（詳細は6章） |

### 1.2 Cloudflare Workers（BFF）

| カテゴリ | 採用技術 | 選定理由 |
|---|---|---|
| 言語 | TypeScript | ユーザー確定事項。Cloudflare Workersの型安全な開発に標準的で、`wrangler`のテンプレートもTypeScriptファーストで整備されている |
| ランタイム/デプロイ | Cloudflare Workers | ユーザー確定事項。クレジットカード登録不要な無料プランがあり、APIキーを秘匿するBFFとして個人開発規模（1日5〜15リクエスト程度）には十分すぎる無料枠（1日10万リクエストまで）を持つ |
| CLIツール | `wrangler` | Cloudflare公式CLI。ローカル開発（`wrangler dev`）・デプロイ（`wrangler deploy`）・シークレット管理（`wrangler secret put`）を一貫して行える |
| ルーティング | 自前実装（`URL.pathname`分岐） | エンドポイントが`/chat`・`/summarize`・`/advice`の3つのみのため、`itty-router`等のルーティングライブラリを追加せず`fetch`ハンドラ内で`switch`分岐する方が薄く保守しやすい |
| 外部AI連携 | Google Gemini API（`gemini-3.1-flash-lite`、`fetch`直叩き） | ユーザー確定事項（Phase 1実測により無料枠内で安定動作を確認済み）。Google公式SDKは追加せず、Workersランタイム標準の`fetch`でHTTPS呼び出しする（Node.js専用SDKはWorkersのEdgeランタイムとの相性リスクがあるため回避） |
| 型バリデーション | 手書きの型ガード関数（`lib/validate.ts`相当） | エンドポイントが3つ・リクエストボディの型が単純なため、zod等の追加は必須ではない。ただし将来的にリクエスト構造が複雑化した場合はzod導入を検討してよい（Phase 1では見送り） |

> ⚠️ 外部ライブラリ（npmパッケージ）は`wrangler`（devDependency）以外、Phase 1では追加しない方針とする。

---

## 2. システム構成図

### 2.1 全体構成（コンポーネント図）

```
┌────────────────────────────────────────────┐
│           iOS App（Swift / SwiftUI）          │
│                                              │
│   Views ←→ ViewModels ←→ SwiftData(ローカルDB) │
│                              Book             │
│                              MemoEntry        │
│                              ConversationLog  │
└───────────────┬──────────────────┬───────────┘
                │(A)                │(B)
     ISBN検索・書影取得      AIチャット／要約／アドバイス生成
     （認証不要・直接呼出）   （共有シークレット経由）
                │                  │
                ▼                  ▼
┌───────────────────────┐  ┌─────────────────────────────┐
│ 国立国会図書館サーチAPI  │  │  Cloudflare Workers（BFF・TS） │
│ (SRU / dcndl形式)       │  │  X-Shared-Secret 検証         │
│ https://ndlsearch.ndl.  │  │  POST /chat・/summarize・     │
│ go.jp/api/sru           │  │  /advice                     │
└───────────────────────┘  └───────────────┬─────────────┘
                                              │ 検証OKの場合のみ
                                              ▼
                                  ┌─────────────────────────┐
                                  │   Google Gemini API       │
                                  │   gemini-3.1-flash-lite   │
                                  │  （GEMINI_API_KEYで認証）  │
                                  └─────────────────────────┘
```

iOSアプリはGemini APIキーを一切保持しない。(A)のNDL APIルートはBFF不要（認証不要・個人非営利利用のため）、(B)のGemini APIルートのみCloudflare Workersを経由する。

### 2.2 フロー詳細：本の登録（FR-01・FR-02）

```
[カメラ映像]
     │ VisionKit DataScannerViewController
     │ .barcode(symbologies: [.ean13])
     ▼
[13桁バーコード検出]
     │
     ├─ 978/979で始まらない → スキャン継続（画面に留まる）
     │
     ▼ 978/979で始まる（ISBN-13）
[NDLSearchService.fetchBookInfo(isbn:)]
     │ GET https://ndlsearch.ndl.go.jp/api/sru
     │   ?operation=searchRetrieve&query=isbn%3D{ISBN}
     │   &recordSchema=dcndl&recordPacking=xml
     │ タイムアウト：10秒／認証不要
     ▼
┌──────────────┬───────────────────┬──────────────────────┐
│ 0件 or        │ 1件以上検出        │ 通信失敗・タイムアウト・  │
│ XMLパース不可  │ （先頭1件を採用）   │ 5xxエラー               │
│ 「該当する書籍  │ dc:title / dc:    │ 「書籍情報の取得に       │
│  情報が見つか   │ creator / 書影を   │  失敗しました」          │
│  りませんでした」│ 抽出しSCR-04へ     │                        │
└──────────────┴───────────────────┴──────────────────────┘
     │（いずれもエラー時）→「手入力で登録する」ボタン表示（FR-02導線）
     ▼（正常系）
[SCR-04 書誌情報確認画面] --「この本を登録する」--> BookRegistrationViewModel.save()
     │
     ▼
[SwiftData: modelContext.insert(Book)] → SCR-01へ遷移

※ FR-02（手入力）は上記フローの「手入力で登録する」ボタンから独立して開始することもできる。
   ManualEntryFormViewModel.save() が直接 SwiftData に Book を insert する（ネットワーク通信なし）。
```

### 2.3 フロー詳細：AI連携（FR-04対話・FR-05要約・FR-09アドバイス生成、Cloudflare Workers経由）

`/chat`・`/summarize`・`/advice`は同一の認証・エラーハンドリングパターンを共有する。差分は末尾の表を参照。

```
[iOS: AIChatViewModel / SummaryViewModel / MemoEditorViewModel・AIChatViewModel（FR-09トリガー元）]
     │ CloudflareWorkersClient.chat(...) / .summarize(...) / .generateAdvice(...)
     │ POST {CLOUDFLARE_WORKERS_URL}/chat  or  /summarize  or  /advice
     │ Header: X-Shared-Secret: {WORKERS_SHARED_SECRET}
     │ タイムアウト：15秒
     ▼
┌─────────────────────────── Cloudflare Workers ───────────────────────────┐
│  src/index.ts（fetchハンドラ、pathnameで振り分け）                          │
│        │                                                                  │
│  lib/auth.ts：X-Shared-Secretヘッダーと環境変数WORKERS_SHARED_SECRETを比較   │
│        │                                                                  │
│        ├─ 不一致 → Gemini APIを呼び出さずHTTP 401を返す（FR-06 No.6）        │
│        │                                                                  │
│        └─ 一致 → routes/chat.ts or routes/summarize.ts or routes/advice.ts │
│                        │                                                  │
│                lib/gemini.ts：Gemini API呼び出し                           │
│                （gemini-3.1-flash-lite、環境変数GEMINI_API_KEYで認証）        │
└──────────────────────────────┬────────────────────────────────────────────┘
                                │
                     ┌──────────┴──────────┬───────────────────┐
                     ▼                     ▼                   ▼
              200: 応答テキストを      429: 無料枠超過       5xx/タイムアウト
              JSONで返却              （429を透過）          （Workers側エラー）
                     │                     │                   │
                     ▼                     ▼                   ▼
    iOS: SCR-07/SCR-08に表示        「利用上限に達しました」「AIとの通信に失敗しました」
    /advice はMemoEntry.dailyAdvice                            「再試行」ボタン表示
    に保存しSCR-05の付箋（常時表示）に反映
    （画面遷移をブロックしないバックグラウンド処理。2.3補足参照）
```

> `/advice`（FR-09）は`/chat`・`/summarize`と異なり、ユーザーの明示操作（ボタン押下）を起点とせず、SCR-06「いいえ」選択時・SCR-07対話終了時に**自動的に**バックグラウンドでトリガーされる。レスポンス待機中も画面遷移をブロックしない点が最大の差分（詳細は末尾の差分表を参照）。

#### 処理の補足

| 処理 | 使用API / メソッド | 認証方式 |
|---|---|---|
| バーコードスキャン | VisionKit `DataScannerViewController.startScanning()` | なし（デバイスローカル処理） |
| 書誌情報取得（FR-01） | `NDLSearchService.fetchBookInfo(isbn:)` → NDL SRU API `GET /api/sru` | 認証不要（個人・非営利利用） |
| 手入力登録（FR-02） | `ManualEntryFormViewModel.save()` → SwiftData `insert(Book)` | なし（ローカル処理） |
| メモ記録（FR-03） | `MemoEditorViewModel.save()` → SwiftData `insert`/`update(MemoEntry)` | なし（ローカル処理） |
| AI対話（FR-04） | `CloudflareWorkersClient.chat()` → Workers `POST /chat` → `lib/gemini.ts` → Gemini API | `X-Shared-Secret`ヘッダー（Workers側）＋`GEMINI_API_KEY`（Workers→Gemini間） |
| 要約生成（FR-05） | `CloudflareWorkersClient.summarize()` → Workers `POST /summarize` → `lib/gemini.ts` → Gemini API | 同上 |
| アドバイス生成（FR-09） | `CloudflareWorkersClient.generateAdvice()` → Workers `POST /advice` → `lib/gemini.ts` → Gemini API | 同上 |
| 削除（FR-07） | `BookshelfViewModel.deleteBook()` / `BookDetailViewModel.deleteMemo()` → SwiftData `delete()` | なし（ローカル処理） |

#### `/chat`・`/summarize`・`/advice`の差分

| 項目 | `POST /chat`（FR-04） | `POST /summarize`（FR-05） | `POST /advice`（FR-09） |
|---|---|---|---|
| 呼び出しタイミング | AI対話の各ターン（往復のたび） | 「要約を作成する」ボタンタップ時のみ | メモ保存後、対話スキップ時（SCR-06「いいえ」）または対話終了時（SCR-07終了）に自動トリガー |
| トリガー主体 | ユーザー操作（回答送信） | ユーザー操作（ボタンタップ） | アプリ側の自動トリガー（ユーザーの追加操作は不要） |
| リクエストボディ | `bookTitle`・`memoContent`・`conversationHistory` | `bookTitle`・`memos`（日付＋本文の配列）・`conversationLogs` | `bookTitle`・`memoContent`・`conversationTurns`（対話ログがない場合は空配列） |
| レスポンス | 次の質問テキスト1件 | 要約テキスト1件 | アドバイステキスト1件 |
| 保存先 | `ConversationLog.turns`（会話終了時にまとめて保存） | `Book.cachedSummary` / `Book.cachedSummaryGeneratedAt` | `MemoEntry.dailyAdvice` |
| 画面遷移への影響 | SCR-07滞在中に同期的に待機 | ボタンタップ後、SCR-08内で結果を待機 | 画面遷移をブロックしない（レスポンス未受信のままSCR-05等へ遷移可能。生成完了後にSCR-05の付箋〔常時表示〕へ反映） |

---

## 3. リポジトリ構成（全体像）

個人開発の単一リポジトリ内に、iOSアプリとCloudflare Workersのプロジェクトをサブディレクトリで分離する。

```
MyBooksMemo/                        # リポジトリルート
├── MyBooksMemo.xcodeproj/          # Xcodeプロジェクトファイル
├── MyBooksMemo/                    # iOSアプリのソース（4章で詳細）
├── workers/                        # Cloudflare Workers（BFF）のソース（5章で詳細）
├── design/                         # 設計書一式（本ファイルを含む）
├── README.md
└── .gitignore
```

---

## 4. iOSアプリのディレクトリ構成（MVVM）

```
MyBooksMemo/
├── MyBooksMemoApp.swift                     # Appエントリポイント。SwiftDataのModelContainer初期化（Book/MemoEntry/ConversationLogをスキーマ登録）
├── Models/
│   ├── Book.swift                           # @Model定義。書誌情報＋要約キャッシュ、MemoEntry/ConversationLogへのカスケード削除リレーションシップ
│   ├── MemoEntry.swift                      # @Model定義。1冊1日1件のメモレコード
│   └── ConversationLog.swift                # @Model定義。AI対話ログ（ConversationTurn配列を保持）
├── Views/
│   ├── Bookshelf/
│   │   ├── BookshelfView.swift              # SCR-01 本棚一覧画面
│   │   └── BookCardView.swift               # 本カードUI（左スワイプ削除ボタンを含む）
│   ├── BookRegistration/
│   │   ├── BarcodeScannerView.swift         # SCR-02 DataScannerViewControllerのUIViewControllerRepresentableラッパー
│   │   ├── ManualEntryFormView.swift        # SCR-03 手入力フォーム（PhotosPicker使用）
│   │   └── BookConfirmationView.swift       # SCR-04 書誌情報確認画面
│   ├── BookDetail/
│   │   ├── BookDetailView.swift             # SCR-05 本詳細画面（メモ一覧タブ・要約タブの親コンテナ、TabView）
│   │   ├── MemoListView.swift               # メモ一覧タブの中身（左スワイプ削除ボタンを含む）。メモカードの「今日のアドバイス」付箋（常時表示、FR-09）を含む
│   │   ├── MemoEditorView.swift             # SCR-06 メモ入力画面
│   │   └── SummaryView.swift                # SCR-08 要約タブ
│   └── AIChat/
│       └── AIChatView.swift                 # SCR-07 AI対話画面（チャットUI、常時「終了する」ボタン表示）
├── ViewModels/
│   ├── BookshelfViewModel.swift             # 本棚一覧の取得・本単位削除（カスケード）ロジック
│   ├── BookRegistrationViewModel.swift      # スキャン結果処理・NDL API呼び出し・登録保存
│   ├── ManualEntryFormViewModel.swift       # 手入力フォームのバリデーション・保存
│   ├── BookDetailViewModel.swift            # メモ一覧取得・当日メモ判定・メモ単位削除（同日ConversationLog連動削除）。「今日のアドバイス」付箋（常時表示）の状態判定（未生成/生成中/生成成功/生成失敗、FR-09）・再試行トリガーも担う
│   ├── MemoEditorViewModel.swift            # メモ本文バリデーション・保存（新規/上書き判定）。DLG-04「いいえ」選択時、`CloudflareWorkersClient.generateAdvice()`をバックグラウンドでトリガーする（FR-09、画面遷移はブロックしない）
│   ├── AIChatViewModel.swift                # /chat呼び出し・往復管理・終了条件判定（5往復 or 終了ボタン）。対話終了時、`CloudflareWorkersClient.generateAdvice()`をバックグラウンドでトリガーする（FR-09、画面遷移はブロックしない）
│   └── SummaryViewModel.swift               # /summarize呼び出し・cachedSummary表示/更新
├── Services/
│   ├── APIClient.swift                      # URLSessionベースの薄い共通通信ラッパー（タイムアウト指定・HTTPステータス→APIErrorへの変換・ログ出力）
│   ├── NDLSearchService.swift               # 国立国会図書館サーチAPI（SRU）呼び出し・XMLパース（dc:title/dc:creator/書影抽出）
│   └── CloudflareWorkersClient.swift        # Cloudflare Workers `/chat`・`/summarize`・`/advice`呼び出し。X-Shared-Secretヘッダー付与
├── Utilities/
│   ├── Config.swift                         # Info.plist経由でCLOUDFLARE_WORKERS_URL・WORKERS_SHARED_SECRETを読み取る（7章参照）
│   └── APIError.swift                       # 共通エラー型（timeout/network/unauthorized/serverError/decodingError）。FR-06のエラーメッセージトーン統一に対応
├── Resources/
│   └── Assets.xcassets                      # プレースホルダー画像（表紙なし用）等
└── Info.plist                               # NSCameraUsageDescription、Build Settings変数の参照キー（CloudflareWorkersURL・WorkersSharedSecret）
```

### 各ファイルの責務（抜粋・補足）

| ファイル | 責務 |
|---|---|
| `Models/Book.swift` | `@Model`。`memoEntries`・`conversationLogs`への`@Relationship(deleteRule: .cascade)`を定義する唯一の場所。FR-07の本単位カスケード削除の実体はここ |
| `Services/APIClient.swift` | `NDLSearchService`と`CloudflareWorkersClient`の両方が依存する共通層。タイムアウト値（10秒/15秒）は呼び出し元が指定し、ここでは汎用的な`send(request:timeout:)`のみ提供する。FR-06共通ルール（自動リトライなし・ログ出力）をここに集約する |
| `Services/CloudflareWorkersClient.swift` | `Config.swift`から`CLOUDFLARE_WORKERS_URL`・`WORKERS_SHARED_SECRET`を読み取り、`/chat`・`/summarize`・`/advice`のリクエスト生成とレスポンスDecodeを担う。ViewModelはこのクライアントのメソッドを呼ぶだけでよい。`/advice`（`generateAdvice()`）は他2エンドポイントと異なり、呼び出し元（`MemoEditorViewModel`・`AIChatViewModel`）がレスポンスを`await`で待たずFire-and-forget的に呼ぶ（画面遷移をブロックしないため） |
| `Utilities/Config.swift` | ハードコードされたシークレットをコードに持たせないための唯一の読み取り窓口。`Bundle.main.object(forInfoDictionaryKey:)`でInfo.plist値を取得する（7章参照） |
| `Views/BookRegistration/BarcodeScannerView.swift` | UIKit製`DataScannerViewController`をSwiftUIから使うための`UIViewControllerRepresentable`。カメラ権限ハンドリング（未許可/拒否済み）もここで行う |

---

## 5. Cloudflare Workersのディレクトリ構成

```
workers/
├── src/
│   ├── index.ts                  # fetchハンドラのエントリポイント。pathnameで/chat・/summarize・/adviceに振り分け、それ以外は404を返す
│   ├── routes/
│   │   ├── chat.ts                # POST /chat ハンドラ。リクエストボディの検証→プロンプト構築→lib/gemini.ts呼び出し→JSON整形
│   │   ├── summarize.ts           # POST /summarize ハンドラ。リクエストボディの検証→プロンプト構築→lib/gemini.ts呼び出し→JSON整形
│   │   └── advice.ts              # POST /advice ハンドラ。リクエストボディ（bookTitle・memoContent・conversationTurns）の検証→プロンプト構築→lib/gemini.ts呼び出し→JSON整形
│   ├── lib/
│   │   ├── auth.ts                # X-Shared-Secretヘッダーと環境変数WORKERS_SHARED_SECRETの比較関数。不一致時は401 Responseを返す
│   │   ├── gemini.ts              # Gemini APIクライアント（fetchラッパー）。モデル名(gemini-3.1-flash-lite)とGEMINI_API_KEYをここに集約
│   │   └── validate.ts            # リクエストボディの型ガード関数（必須フィールドの存在チェック）
│   └── types.ts                   # ChatRequest/ChatResponse/SummarizeRequest/SummarizeResponse/AdviceRequest/AdviceResponseの型定義
├── wrangler.jsonc                 # Workers設定（name・main・compatibility_date）。GEMINI_API_KEY等の秘密値はここに書かない
├── package.json                   # devDependency: wrangler, typescript のみ
├── tsconfig.json
└── .dev.vars                      # ローカル開発用の環境変数（GEMINI_API_KEY・WORKERS_SHARED_SECRET）。.gitignore対象
```

### 各ファイルの責務

| ファイル | 責務 |
|---|---|
| `src/index.ts` | ルーティングのみを担う。ビジネスロジック（Geminiへのプロンプト構築等）は書かない |
| `src/lib/auth.ts` | FR-06共通ルールNo.6の実体。`chat.ts`・`summarize.ts`・`advice.ts`の3つ全てから呼ばれる共通関数として1箇所に集約し、認証ロジックの重複を防ぐ |
| `src/lib/gemini.ts` | Gemini APIとの通信を1箇所に集約するシングルトン的モジュール。モデル名を変更する場合もこのファイルのみ変更すればよい |
| `src/routes/chat.ts` / `summarize.ts` / `advice.ts` | それぞれのエンドポイント固有のプロンプト文言・リクエスト整形のみを担う。認証・Gemini呼び出しの実処理は`lib/`に委譲する |

---

## 6. SwiftDataのモデル定義方針

### 6.1 モデル一覧とプロパティ

```swift
import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var isbn: String?                  // 手入力登録時はnilの場合あり
    var coverImageData: Data?          // NDL取得画像 or PhotosPickerで選択した画像をローカル保存（オフライン閲覧のため。7.1参照）
    var createdAt: Date
    var cachedSummary: String?               // FR-05：要約キャッシュ
    var cachedSummaryGeneratedAt: Date?      // FR-05：要約の最終生成日時

    @Relationship(deleteRule: .cascade, inverse: \MemoEntry.book)
    var memoEntries: [MemoEntry] = []

    @Relationship(deleteRule: .cascade, inverse: \ConversationLog.book)
    var conversationLogs: [ConversationLog] = []

    init(id: UUID = UUID(), title: String, author: String, isbn: String? = nil,
         coverImageData: Data? = nil, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.author = author
        self.isbn = isbn
        self.coverImageData = coverImageData
        self.createdAt = createdAt
    }
}

@Model
final class MemoEntry {
    @Attribute(.unique) var id: UUID
    var date: Date          // Calendar.current.startOfDay(for:)で正規化した「日」の値。FR-03の1日1件判定・FR-07の同日ConversationLog検索に使用
    var contentItems: [String]  // FR-03：箇条書き形式の各項目（配列の各要素がSCR-06の入力フォーム1つに対応）。SwiftDataはString配列をそのまま属性として永続化できるため別モデル化しない。保存前に空文字（前後の空白のみを含む場合を含む）の要素を除外済みの状態でここに格納する。Gemini APIへ送信する際（FR-04・FR-05・FR-09）は各要素を改行で連結した1つの文字列として扱う
    var dailyAdvice: String?  // FR-09：自動生成される「今日のアドバイス」。生成トリガー未発生・生成中・生成失敗はいずれもnilのまま（値の有無の2値のみを表す。状態の切り分けはUI側で行う）
    var book: Book?          // Bookからの@Relationship(inverse:)により対になる。カスケード削除の起点はBook側

    init(id: UUID = UUID(), date: Date, contentItems: [String], dailyAdvice: String? = nil, book: Book? = nil) {
        self.id = id
        self.date = date
        self.contentItems = contentItems
        self.dailyAdvice = dailyAdvice
        self.book = book
    }
}

struct ConversationTurn: Codable {
    var question: String
    var answer: String
}

@Model
final class ConversationLog {
    @Attribute(.unique) var id: UUID
    var date: Date                       // MemoEntry.dateと同じ正規化ルールで保存し、FR-07のメモ単位削除時に同日ログを特定する
    var turns: [ConversationTurn]        // Codable構造体配列。SwiftDataはCodable準拠の値型配列をそのまま属性として永続化できるため、別モデル化しない
    var book: Book?

    init(id: UUID = UUID(), date: Date, turns: [ConversationTurn] = [], book: Book? = nil) {
        self.id = id
        self.date = date
        self.turns = turns
        self.book = book
    }
}
```

### 6.2 リレーションシップとカスケード削除の設計

| リレーションシップ | deleteRule | 実装箇所 |
|---|---|---|
| `Book.memoEntries` → `MemoEntry` | `.cascade` | `Book`側に`@Relationship(deleteRule: .cascade, inverse: \MemoEntry.book)`を定義。`Book`削除時、紐づく全`MemoEntry`が自動削除される |
| `Book.conversationLogs` → `ConversationLog` | `.cascade` | 同上パターン。`Book`削除時、紐づく全`ConversationLog`が自動削除される |
| `MemoEntry` ⇔ `ConversationLog`（同日） | リレーションシップなし（アプリケーションロジック） | **意図的にSwiftDataのリレーションシップを定義しない。** 理由は6.3参照 |

`requirements.md`のFR-07で「`bookId`」と表記されている項目は、SwiftDataでは`Book`への`@Relationship`（`book: Book?`プロパティ）として実装する。UUIDを直接持つ代わりにオブジェクト参照を持つ設計とすることで、SwiftDataのカスケード削除機構をそのまま活用できる。

### 6.3 メモ単位削除時の同日ConversationLog削除（FR-07 Step7）について

FR-07では「メモ削除時、同一`bookId`・同一`date`の`ConversationLog`も削除するが、`Book.cachedSummary`は保持する」という粒度の異なる削除ルールが定義されている。これは`MemoEntry`と`ConversationLog`という**兄弟関係**の削除連動であり、SwiftDataの`@Relationship`カスケード（親→子の一方向）では表現できない。

そのため、`MemoEntry`と`ConversationLog`の間に直接のリレーションシップは定義せず、`BookDetailViewModel.deleteMemo()`内でアプリケーションロジックとして以下を実施する。

```swift
// BookDetailViewModel.deleteMemo() の処理イメージ
func deleteMemo(_ memo: MemoEntry, context: ModelContext) {
    let targetDate = memo.date
    let targetBookID = memo.book?.id

    // 同一book・同一dateのConversationLogを明示的に検索して削除する
    let descriptor = FetchDescriptor<ConversationLog>(
        predicate: #Predicate { $0.date == targetDate && $0.book?.id == targetBookID }
    )
    if let logs = try? context.fetch(descriptor) {
        logs.forEach { context.delete($0) }
    }

    context.delete(memo)   // Book.cachedSummaryには触れない（FR-07の仕様通り）
    try? context.save()
}
```

---

## 7. 通信層の設計

### 7.1 設計方針：軽量ラッパー方式

`URLSession`を各Viewから直接叩くのではなく、`Services/`配下に軽量なラッパーを1層挟む。

- **`APIClient.swift`**：どちらの外部通信（NDL API・Cloudflare Workers）にも共通する「タイムアウト指定付きリクエスト送信」「HTTPステータスコード→`APIError`への変換」「FR-06共通ルールNo.5のログ出力（ステータスコード・エンドポイント・タイムスタンプのみ。本文は出力しない）」を1箇所に集約する
- **`NDLSearchService.swift`**：`APIClient`を使ってNDL SRU APIを呼び出し、XMLレスポンスをパースして`(title, author, coverImageData)`相当の値を返す。取得した書影画像は`Book.coverImageData`としてダウンロード時点でローカル保存する（NF-06「過去に保存済みデータの閲覧はオフライン可能」の要件を満たすため、表示のたびにNDL側URLへ再アクセスしない設計とする）
- **`CloudflareWorkersClient.swift`**：`APIClient`を使って`/chat`・`/summarize`・`/advice`を呼び出す。`X-Shared-Secret`ヘッダーの付与、`Codable`によるリクエスト/レスポンスの型安全な変換を担う

Alamofire等のHTTPライブラリは追加しない。理由：呼び出し先が2種類のみ・リクエスト頻度が1日5〜15件程度と小規模・`URLSession`のasync/await APIで十分に簡潔に書けるため、追加の依存を持つメリットが薄い。

### 7.2 タイムアウト・エラーハンドリングの実装箇所

| ルール | 実装箇所 |
|---|---|
| NDL API：10秒タイムアウト | `NDLSearchService`が`APIClient.send(request:timeout: 10)`を呼ぶ |
| Gemini API（Workers経由）：15秒タイムアウト | `CloudflareWorkersClient`が`APIClient.send(request:timeout: 15)`を呼ぶ |
| 自動リトライなし（FR-06 No.3） | `APIClient`にリトライ機構を実装しない。「再試行」ボタンはView側のユーザー操作から同じメソッドを再度呼ぶだけ |
| エラーメッセージのトーン統一（FR-06 No.4） | `Utilities/APIError.swift`の`localizedDescription`相当のcomputed propertyで、Viewに表示する文言を一元管理する |
| ログ出力（FR-06 No.5） | `APIClient`内で`print()`または`os.Logger`により、ステータスコード・エンドポイント・タイムスタンプのみ出力する。メモ本文・対話内容は引数として渡さない設計にする（そもそもログ出力関数にリクエストボディを渡さない） |

---

## 8. Xcodeプロジェクトの構成

### 8.1 依存管理方針

Swift Package Manager（SPM）を使用するが、**Phase 1では外部パッケージを一切追加しない**。以下の標準フレームワークのみで全要件を満たせることを確認済み。

| フレームワーク | 用途 |
|---|---|
| SwiftUI | 全画面のUI構築 |
| SwiftData | ローカル永続化（`Book`・`MemoEntry`・`ConversationLog`） |
| VisionKit | `DataScannerViewController`によるバーコードスキャン（FR-01） |
| PhotosUI | `PhotosPicker`による表紙画像選択（FR-02） |
| Foundation | `URLSession`（通信）・`XMLParser`（NDL APIレスポンスのXMLパース）・`Calendar`（日付正規化） |

外部ライブラリが必要になる箇所は現時点でない。将来的にXML構造が複雑化しパースが困難になった場合のみ、XMLパースライブラリの追加を検討する（Phase 1ではスコープ外）。

### 8.2 マルチターゲット構成

Phase 1はアプリターゲット1つのみ（ウィジェット・Watchアプリ等は`requirements.md`の「作らないこと」により対象外）。

### 8.3 シークレットのビルド設定への埋め込み方法

`WORKERS_SHARED_SECRET`・`CLOUDFLARE_WORKERS_URL`をソースコードにハードコードしないため、xcconfigファイル経由でXcodeのBuild Settingsに注入し、Info.plist経由でアプリから読み取る。

1. リポジトリに**コミットする**テンプレートファイル `Secrets.xcconfig.example` を用意する
2. 開発者は`Secrets.xcconfig.example`を`Secrets.xcconfig`としてコピーし、実際の値を記入する（`Secrets.xcconfig`は`.gitignore`対象）
3. Xcodeプロジェクトの Build Settings → Configurations で、Debug/Release両方の Base Configuration File に `Secrets.xcconfig` を指定する
4. `Info.plist`に以下のキーを追加し、Build Settings変数を参照させる

```xml
<key>CloudflareWorkersURL</key>
<string>$(CLOUDFLARE_WORKERS_URL)</string>
<key>WorkersSharedSecret</key>
<string>$(WORKERS_SHARED_SECRET)</string>
```

5. `Utilities/Config.swift`で`Bundle.main.object(forInfoDictionaryKey:)`により読み取る

```swift
enum Config {
    static var cloudflareWorkersURL: URL {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "CloudflareWorkersURL") as? String,
              let url = URL(string: string) else {
            fatalError("CloudflareWorkersURL が Info.plist に設定されていません")
        }
        return url
    }

    static var workersSharedSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "WorkersSharedSecret") as? String ?? ""
    }
}
```

> ⚠️ **xcconfigファイルの`//`エスケープに注意**：`.xcconfig`ファイルでは`//`が行コメント開始と解釈されるため、URLをそのまま`CLOUDFLARE_WORKERS_URL = https://xxx.workers.dev`と書くと`https:`以降が切り捨てられる。`CLOUDFLARE_WORKERS_URL = https:/$()/xxx.workers.dev`のように`$()`（空マクロ）を挟んでスラッシュの連続を回避すること。`MyBooksMemo_setup.md`にも手順として明記する。

> ⚠️ この方式はNF-02が定義する「最低限の悪用対策」の範囲内であり、コンパイル済みアプリのInfo.plistから`WORKERS_SHARED_SECRET`の値自体を完全に隠蔽するものではない（IPAを解析されれば読み取り得る）。個人利用アプリでの脅威モデルとして許容する、というrequirements.md NF-02の前提を踏襲する。

---

## 9. Cloudflare Workersのプロジェクト構成・デプロイ方法

### 9.1 `wrangler.jsonc`（例）

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "mybooksmemo-workers",
  "main": "src/index.ts",
  "compatibility_date": "2026-08-05"
}
```

秘密値（`GEMINI_API_KEY`・`WORKERS_SHARED_SECRET`）は`wrangler.jsonc`の`vars`には書かない（平文でリポジトリに残るため）。代わりにWrangler Secretsとして登録する。

### 9.2 デプロイ手順（初回）

```bash
cd workers
npm install
npx wrangler login                              # Cloudflareアカウント連携（ブラウザ認証）
npx wrangler secret put GEMINI_API_KEY          # 対話式でGemini APIキーを入力
npx wrangler secret put WORKERS_SHARED_SECRET   # 対話式で共有シークレットを入力
npx wrangler deploy
```

デプロイ完了時に払い出される`https://mybooksmemo-workers.{アカウント名}.workers.dev`のURLを、iOS側の`Secrets.xcconfig`の`CLOUDFLARE_WORKERS_URL`に設定する。

### 9.3 更新デプロイ

```bash
cd workers
npx wrangler deploy
```

秘密値は変更がない限り再設定不要（`wrangler secret put`で設定した値はデプロイのたびに消えない）。

### 9.4 ローカル開発

```bash
cd workers
cp .dev.vars.example .dev.vars   # GEMINI_API_KEY・WORKERS_SHARED_SECRETを記入（.gitignore対象）
npx wrangler dev
```

### 9.5 無料プランの範囲であることの確認

| 項目 | Cloudflare Workers Free プランの制限 | 本プロジェクトでの想定 |
|---|---|---|
| リクエスト数 | 1日10万リクエストまで（UTC 0時にリセット） | 想定利用量は1日5〜15リクエスト程度。上限に対して十分な余裕がある |
| CPU時間 | 1リクエストあたり10ミリ秒まで | Gemini APIへの`fetch`待ち時間はCPU時間に計上されない（CPU時間はJavaScriptコード自体の実行時間のみを計測し、`fetch`等のI/O待ち時間は含まれない）。本Workerの処理はヘッダー検証とJSON整形のみで、10ミリ秒で十分収まる |
| クレジットカード登録 | 不要 | Phase 1決定事項（progress.md記載）の通り、無料プランはクレジットカード登録なしで利用開始できる |

以上より、Cloudflare Workers Freeプランの範囲内で運用可能である。

---

## 10. 環境変数一覧

> この一覧は `MyBooksMemo_setup.md` チェックリストA（APIキー・認証情報の取得）に転記する。

### 10.1 Cloudflare Workers側（`workers/.dev.vars` ローカル開発用。本番は`wrangler secret put`で設定しファイルには残さない）

```bash
# .dev.vars（.gitignore対象。本番はwrangler secret putで別途設定する）

# Google Gemini API
GEMINI_API_KEY=your-gemini-api-key-here          # Gemini API呼び出し用のAPIキー。Workers側のみで保持し、iOSアプリには一切渡さない

# iOSアプリ ⇔ Cloudflare Workers間の認証
WORKERS_SHARED_SECRET=your-shared-secret-here    # iOSアプリからのリクエスト正当性検証用の共有シークレット
```

### 10.2 iOSアプリ側（`Secrets.xcconfig`。`.gitignore`対象、`Secrets.xcconfig.example`のみコミットする）

```
// Secrets.xcconfig.example

CLOUDFLARE_WORKERS_URL = https:/$()/mybooksmemo-workers.example.workers.dev
WORKERS_SHARED_SECRET = your-shared-secret-here
```

### 環境変数の取得場所

| 環境変数 | 配置場所 | 取得場所 |
|---|---|---|
| `GEMINI_API_KEY` | Cloudflare Workers側のみ（`wrangler secret put`） | Google AI Studio（`https://aistudio.google.com/`）→ APIキー発行画面 |
| `WORKERS_SHARED_SECRET` | 両側（Workers：`wrangler secret put` / iOS：`Secrets.xcconfig`） | 開発者自身が任意のランダム文字列を生成して決める（例：`openssl rand -hex 32`）。両側で同じ値を設定する |
| `CLOUDFLARE_WORKERS_URL` | iOSアプリ側のみ（`Secrets.xcconfig`） | `wrangler deploy`実行後にターミナルへ出力される`*.workers.dev`のURL |

> ⚠️ `WORKERS_SHARED_SECRET`はiOS側・Workers側の両方に同じ値を設定する必要がある。値を変更する場合は両方を同時に更新すること（片方だけ更新すると全リクエストが401になる）。

---

## 要確認事項

- FR-01の書影（cover image）取得方法について：国立国会図書館サーチAPI（SRU、dcndl形式）のレスポンスに書影の画像URLが実際にどのXML要素で含まれるか（または書影が別途サムネイルAPIから取得する方式なのか）は未検証。本ドキュメントでは「XMLパースにより書影情報を抽出する」という方針までを設計したが、具体的なXML要素名・取得方式は`detailed_design.md`作成前、またはFR-01実装着手前のpre-implementation-check（実機での実際のAPIレスポンス確認）で確定させる必要がある
- Cloudflare Workersのアカウント作成そのものにクレジットカード登録が不要である点は、progress.mdの既存決定事項（Phase 1調査時の判断）を踏襲した。Workers単体の無料プラン制限（リクエスト数・CPU時間）は本ドキュメント作成時にCloudflare公式ドキュメントで再確認済み（9.5参照）
