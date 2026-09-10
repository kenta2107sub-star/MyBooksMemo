# MyBooksMemo

> 読書メモ・言語化トレーニングアプリ（個人利用専用のiOSアプリ）

---

## 目次

- [概要](#概要)
- [機能](#機能)
- [技術スタック](#技術スタック)
- [セットアップ](#セットアップ)
- [使い方](#使い方)
- [ディレクトリ構成](#ディレクトリ構成)
- [環境変数](#環境変数)
- [よくある問題](#よくある問題)

---

## 概要

本を読んでも内容を忘れてしまう、読み返しに時間がかかる。そんな悩みを解消するための、個人利用専用の読書メモアプリです。

バーコードをスキャンするだけで本を登録し、1冊につき1日1件のペースでメモを記録します。記録したメモはGemini APIとの対話を通じて深掘りでき、言語化の質を上げるトレーニングになります。メモが貯まった本は、ボタン一つでこれまでの気づきをAIが要約してくれます。

このアプリは開発者本人のiPhoneにXcodeから直接インストールして使うものです。App Storeでの配布は行いません。

---

## 機能

- **バーコードスキャンでの本登録**：ISBNバーコードを読み取り、国立国会図書館サーチAPIから書誌情報（タイトル・著者・表紙）を自動取得して登録する
- **手入力での本登録**：バーコードが読み取れない場合や情報を修正したい場合に、タイトル・著者・表紙画像を手動で入力する
- **メモ記録**：1冊につき1日1件、読書内容や気づきを箇条書き形式で記録する
- **AI対話フィードバック**：記録したメモに対してGemini APIが質問を投げかけ、最大5往復のチャットで言語化を深掘りする。送信済みの回答は、通信失敗時や応答待ち中の終了でも対話ログに残す
- **本単位の要約生成**：蓄積したメモとAI対話ログをもとに、ボタンを押したタイミングでAIが本ごとの気づきを要約する。生成結果はキャッシュされ、メモをすべて削除した後も閲覧できるが、再作成には新しいメモが必要
- **今日のアドバイスの自動生成**：メモ記録後、対話の有無にかかわらずAIがその日の気づきに対する一言アドバイスを自動生成し、メモカードに常時表示する
- **AI対話ログの振り返り**：過去に行ったAI対話を読み取り専用で見返せる
- **本・メモ・対話ログの削除**：本単位（メモ・対話ログ・要約もまとめて削除）、メモ単位（同日の対話ログも連動して削除）の2種類の粒度で削除できる
- **Workers入力と認証**：AI機能は共有シークレットを本文の読取・解析より先に検証する。認証済みリクエストはUTF-8で512 KiB以下、文字列合計100,000 Unicodeコードポイント以下に制限し、上限や日付形式に合わない入力はGemini APIへ送信しない

> 2026-09-10時点で、AI対話の送信済み往復の保存、NDL検索の先頭record固定、要約の送信順・無効表示、Gemini応答上限を実装し、回帰検証を完了しています。WorkersのOAuth認証と`workers.dev`への初回公開、認証ヘッダーなしの公開`POST /chat`がWorker固有JSONのHTTP 401を返すことを確認しました。Secrets登録とGeminiの実疎通、正しい共有シークレットでの応答確認は未完了です。

---

## 技術スタック

本アプリは「iOSアプリ（クライアント）」と「Cloudflare Workers（BFF）」の2プロジェクトで構成されています。

### iOSアプリ

| カテゴリ | 技術 |
|---|---|
| 言語 | Swift 5.9系 |
| UIフレームワーク | SwiftUI |
| アーキテクチャ | MVVM |
| 最小対応OS | iOS 17.0 |
| ローカル永続化 | SwiftData |
| バーコードスキャン | VisionKit（`DataScannerViewController`） |
| 画像選択 | PhotosUI（`PhotosPicker`） |
| 通信 | `URLSession`（async/await） |

### Cloudflare Workers（BFF）

| カテゴリ | 技術 |
|---|---|
| 言語 | TypeScript |
| ランタイム / デプロイ先 | Cloudflare Workers |
| CLIツール | `wrangler` |
| 外部AI連携 | Google Gemini API（`gemini-3.1-flash-lite`） |

> BFF（Backend for Frontend）とは、iOSアプリの手前に置く中継サーバーのことです。GeminiのAPIキーをアプリ内に持たせず、この中継サーバー側だけで管理するために使っています。

---

## セットアップ

このアプリは開発者本人が自分のiPhoneにインストールして使うためのものです。Cloudflare Workers（BFF）は実際にクラウドへデプロイして使用します。

### 前提条件

- Simulator検証：Xcode 15.2 / iOS SDK 17.2（2026-09-01の実測環境）
- 所有者iPhoneへのインストール：USB接続を優先し、ロック解除、Macの信頼、Developer Modeを確認したうえでXcodeのRun destinationに安定して列挙されること
- Node.js 20以上（`node -v` で確認）
- Google AI Studioで発行したGemini Auth key
- Cloudflareアカウント（料金・カード要否は登録画面の最新表示を確認）
- Apple Developer Programの有料Team

> 所有者iPhoneはUSB、CoreDevice、XcodeのRun destinationで安定して列挙でき、明示的なUnsupported OSエラーはありませんでした。再接続時もUSBを優先し、ロック解除、Macの信頼、Developer Mode、Run destinationへの列挙を確認してください。

### セットアップの流れ

```bash
# 1. リポジトリのクローン
git clone {リポジトリのURL}
cd MyBooksMemo

# 2. Cloudflare Workers（BFF）の非破壊検証
cd workers
npm ci
npm run typecheck
npm test
npx wrangler deploy --dry-run

# 3. iOSアプリのシークレット設定
cd ..
cp MyBooksMemo/Secrets.xcconfig.example MyBooksMemo/Secrets.xcconfig
# 本番値は利用者がローカルで直接入力し、ログや会話に出さない

# 4. Xcodeでビルド・実機インストール
open MyBooksMemo.xcodeproj
# 下記の承認ゲートと実機手順に従う
```

CloudflareのOAuth認証と初回公開は完了しています。Secrets登録とGeminiの本番疎通は外部状態を変更するため、それぞれの直前に明示承認を得ます。`wrangler secret put`は実行するたびにWorkerの新バージョンを公開します。

Bundle Identifierは、Appを`com.kenta2107substar.MyBooksMemo`、Testsを`com.kenta2107substar.MyBooksMemoTests`に設定済みです。証明書とProvisioning ProfileのTeam整合性を確認し、自動署名のbuild-for-testing、実機インストール、起動を完了しました。所有者iPhoneでは46件の自動テストと、手入力登録、メモ永続化、削除、オフライン時の安全な失敗と復旧、デバッガなし通常起動を確認済みです。Workersは公開済みですがSecrets登録とGeminiの実疎通が未完了のため、全体の判定は`LIMITED`です。

### 外部サービスの設定

1. **Google Gemini APIキーの発行**：`https://aistudio.google.com/apikey` でログインし、「Create API key」から新規発行する
2. **Cloudflareアカウントの作成**：`https://dash.cloudflare.com/sign-up` から作成する。料金・カード要否は登録時の公式表示を確認する

`.xcconfig`ファイルでのURLの書き方（`//`のエスケープ）など、つまずきやすいポイントを含めた詳しい手順は [`design/MyBooksMemo_setup.md`](./design/MyBooksMemo_setup.md) にまとめています。初めてセットアップする場合はこちらを参照してください。

---

## 使い方

### 本を登録する

本棚一覧画面の「＋」ボタンからカメラを起動し、本のISBNバーコード（978または979で始まる13桁）を読み取ります。国立国会図書館サーチAPIから書誌情報を取得し、確認画面に表示します。

```
タイトル：嫌われる勇気
著者：岸見一郎, 古賀史健
表紙：あり（サムネイル表示）
[この本を登録する]　[情報を修正する]
```

バーコードが読み取れない・情報が見つからない場合は、その場で手入力に切り替えて登録できます。

### 今日のメモを記録する

本の詳細画面から「今日のメモを書く」を選び、箇条書きでその日の気づきを記録します。1冊につき1日1件で、同じ日にもう一度書くと内容が上書きされます。

```
・「主体的である」の章を読み返した
・反応的な自分に気づけた
```

保存後、AIとの対話に進むかどうかを選べます。

### AIと対話して深掘りする

メモの内容をもとに、AIが具体的な場面や次の行動を尋ねてきます。最初の質問が表示されてから回答を送信できます。最大5往復、または「終了する」ボタンでいつでも切り上げられます。通信に失敗した場合も、送信済みの回答を含めて終了できます。

```
AI: 「『自分の意見を言えるようになりたい』とありますが、
     直近で意見を言えなかった具体的な場面はありますか？」
ユーザー: 「今日の会議で発言を求められたが黙ってしまった」
AI: 「そのとき、何を言おうとして、なぜ言えなかったのですか？」
```

対話を終えると、その日の気づきに対する「今日のアドバイス」がメモカードに自動で表示されます。

### 本の要約を作成する

メモが1件以上たまった本の「要約」タブで「要約を作成する」を押すと、日付の新しい順に並べた全メモと、全対話ログをもとにAIが要約を生成します。生成結果は保存され、次にボタンを押すまでは同じ内容を表示し続けます。メモをすべて削除した場合も保存済み要約は読めますが、再作成ボタンは無効になります。

```
【この本から得た気づき】
・「小さな一歩を積み重ねる」という考え方について、3回のメモで繰り返し言及している
・4/12の対話で「完璧主義をやめる」という具体的な行動目標が明確化された

最終生成：2026/08/05
[要約を再作成する]
```

---

## ディレクトリ構成

```
MyBooksMemo/                        # リポジトリルート
├── MyBooksMemo.xcodeproj/          # Xcodeプロジェクトファイル
├── MyBooksMemo/                    # iOSアプリのソース（Models / Views / ViewModels / Services など）
├── MyBooksMemoTests/               # iOSアプリの単体テスト
├── workers/                        # Cloudflare Workers（BFF）のソース
├── design/                         # 設計書一式
├── README.md
└── .gitignore
```

iOSアプリ・Cloudflare Workersそれぞれの詳細なディレクトリ構成は [`design/MyBooksMemo_architecture.md`](./design/MyBooksMemo_architecture.md) を参照してください。

---

## 環境変数

| 変数名 | 必須 | 配置場所 | 説明 |
|---|---|---|---|
| `GEMINI_API_KEY` | ✅ | Cloudflare Workers側のみ（`wrangler secret put`） | Gemini API呼び出し用のAPIキー。iOSアプリには一切渡さない |
| `WORKERS_SHARED_SECRET` | ✅ | 両側（Workers：`wrangler secret put` / iOS：`Secrets.xcconfig`） | iOSアプリからのリクエストを検証するための共有シークレット。両側で同じ値を設定する |
| `CLOUDFLARE_WORKERS_URL` | ✅ | iOSアプリ側のみ（`Secrets.xcconfig`） | `wrangler deploy`実行後に発行されるWorkersのURL |

値そのものはリポジトリに含めません。`GEMINI_API_KEY`はiOS設定・Info.plist・アプリバンドルに保存しません。本番値は利用者が各サービス画面またはローカルの無視対象ファイルへ直接入力し、ログ・Git・会話へ出さないでください。

`WORKERS_SHARED_SECRET`はインストール済みiOSアプリから抽出・再利用され得るため、強固な端末認証ではありません。所有者iPhoneへの直接配布に限る現在の範囲では残余リスクとして扱います。漏えい時はWorkers側とiOS側の値を更新し、配布範囲を広げる場合は認証モデルを見直してください。Cloudflare側の要求量制限は公開時に別途確認します。詳細は [`design/MyBooksMemo_setup.md`](./design/MyBooksMemo_setup.md) を参照してください。

---

## よくある問題

**AIとの対話・要約生成がすべて失敗する**

原因：`WORKERS_SHARED_SECRET`がiOSアプリ側とCloudflare Workers側で一致していません。
対処：`Secrets.xcconfig`の値と、Cloudflare Workersに`wrangler secret put`で登録した値が一字一句同じか確認してください。

**Xcodeのビルドエラーに`CloudflareWorkersURL`関連のメッセージが出る**

原因：`Secrets.xcconfig`がXcodeのBuild Settingsに設定されていません。
対処：Build Settings → Configurations で、Debug・Release両方の Base Configuration File に `Secrets.xcconfig` を指定してください。

**Geminiの応答が長すぎて要約・対話・アドバイスの生成に失敗する**

原因：前後の空白を除いたGemini応答が20,000 Unicodeコードポイントを超えています。
対処：応答は切り詰めず、既存の通信エラーとして表示します。この上限は製品コードと回帰テストで確認済みです。

**AI機能で入力エラーが表示される**

原因：AI機能に送る本文は512 KiB以下、文字列合計は100,000 Unicodeコードポイント以下です。対話履歴は最大5往復、要約用メモは最大1,000件で、要約に含める日付は実在する`yyyy-MM-dd`形式に限ります。
対処：メモや対話履歴を短くするか、要約対象を減らしてから再試行してください。入力が制限を超えた場合、Gemini APIは呼び出されません。
