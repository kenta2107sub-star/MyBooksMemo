# セットアップガイド

> **プロジェクト名**：MyBooksMemo（読書メモ・言語化トレーニングアプリ）
> **対象フェーズ**：Phase 1（MVP）のみ
> **このドキュメントの用途**：開発に着手する前に済ませておく「外部サービスの登録・設定」と、コードが完成したあとに行う「手元での動作確認」の手順をまとめたガイド。上から順に実施すれば、追加で何も調べずに完了できるように書いている。
> **想定読者**：プログラミング経験がない人。「ターミナル」「環境変数」のような言葉が出てくる箇所は、その都度どういうものかを一言添える。
> **関連ドキュメント**：
> - `MyBooksMemo_requirements.md`（このアプリが何をするか＝機能要件・非機能要件）
> - `MyBooksMemo_architecture.md`（技術的な構成・環境変数の一覧）
> - `MyBooksMemo_basic_design.md`（画面仕様。このファイルの後、モック実装の前に作成する）

---

## ⚠️ 開発着手前チェックリスト

このアプリは「iOSアプリ本体」だけでなく、「Cloudflare Workers」という中継サーバー（後述）も使う。
本体を動かす前に、以下のA〜Dをすべて終わらせておく。

### 🔑 A. APIキー・認証情報の取得（設定する値の一覧）

「APIキー」とは、外部のサービスを使わせてもらうための“合言葉”のようなものだと考えてよい。
このアプリで必要になる値は次の3つ。取得方法は後述の「1」「2」で説明する。

| # | 確認項目 | 取得場所 | 環境変数名（設定値の呼び名） | 完了 |
|---|---|---|---|---|
| A-1 | Gemini APIキーを発行済み | Google AI Studio（`https://aistudio.google.com/apikey`） | `GEMINI_API_KEY` | [ ] |
| A-2 | iOSアプリ↔中継サーバー間の合言葉（共有シークレット）を自分で決めた | 自分でランダムな文字列を生成する（手順は後述） | `WORKERS_SHARED_SECRET` | [ ] |
| A-3 | 中継サーバーを公開したあとに発行されるURLを控えた | `wrangler deploy` 実行後にターミナルに表示される | `CLOUDFLARE_WORKERS_URL` | [ ] |

> ⚠️ **プロジェクトのフォルダ直下に `.env` というファイルをすでに作っている場合の注意**
> Phase 1の技術調査でGemini APIキーの動作確認をした際に `.env` ファイルを作った人は、そのファイルは**このアプリの本番の設計では使わない**。
> このアプリでは、APIキーは「2. Cloudflareアカウント作成・Workersセットアップ手順」で説明する `workers/.dev.vars`（手元での確認用）と `wrangler secret put`（公開用）という、別の2箇所に設定し直す。
> `.env` ファイル自体は削除して問題ない（`.gitignore` の設定によりGitに記録はされないが、使われないファイルとして残しておく必要はない）。
>
> ⚠️ **A-1のGemini APIキーは、Phase 1で発行したものを流用せず、必ず新しく発行し直す**（理由は後述の「1. Gemini APIキーの発行手順」を参照）。

### ☁️ B. Cloudflareアカウント作成・Workersセットアップの完了

「Cloudflare Workers」は、GeminiのAPIキーをiOSアプリの中に埋め込まずに済むようにするための、無料の中継サーバーサービス。

| # | 確認項目 | 完了 |
|---|---|---|
| B-1 | Cloudflareのアカウントを作成済み（料金・カード要否は登録画面の最新表示を確認） | [x] |
| B-2 | パソコンにNode.js（`node`コマンドが使える環境）をインストール済み（`node -v` で確認） | [x] |
| B-3 | `npx wrangler login` でCloudflareアカウントとの連携を完了済み | [x] |
| B-4 | 明示承認後、秘密情報未設定で初回`npx wrangler deploy`を実行し、fail closedを維持済み | [x] |
| B-5 | 別の明示承認後、`GEMINI_API_KEY`と`WORKERS_SHARED_SECRET`を対話入力で登録済み | [x] |
| B-6 | `wrangler secret list`で名前だけを確認し、Workers URLを無視対象`Secrets.xcconfig`へ直接転記済み | [x] |

> ⚠️ **C-3の値がWorkers側と一致しないと、iOSアプリからのAI対話・要約生成がすべて失敗する。** 秘密値はCloudflare Workers側にだけ保存され、あとから見返すことができないため、設定した値は忘れないように別途メモしておくこと。

### 📱 C. Xcode側のシークレット設定の完了

Xcode（アプリを作るためのアプリ）に、上で用意した値を教える作業。

| # | 確認項目 | 完了 |
|---|---|---|
| C-1 | `Secrets.xcconfig.example` を `Secrets.xcconfig` という名前でコピー済み | [x] |
| C-2 | `Secrets.xcconfig` に `CLOUDFLARE_WORKERS_URL`（B-6で控えたURL）を記入済み | [x] |
| C-3 | `Secrets.xcconfig` に `WORKERS_SHARED_SECRET`（B-5と同じ値）を記入済み | [x] |
| C-4 | XcodeのBuild Settingsで `Secrets.xcconfig` をDebug・Release両方に設定済み | [x] |

> ⚠️ **C-3はB-5と一字一句同じ値にすること。** iOSアプリ側とCloudflare Workers側で合言葉が1文字でも違うと、すべてのAI関連リクエストが「認証エラー」で失敗する（画面には「AIとの通信に失敗しました」とだけ表示され、原因が合言葉の不一致だとは表示されない）。

### 🖥️ D. ローカル開発環境の準備の完了

| # | 確認項目 | 完了 |
|---|---|---|
| D-1 | Simulator検証で使うXcodeとiOS SDKを実測済み。所有者iPhoneがXcodeのRun destinationに安定して列挙される接続を確認済み | [ ] |
| D-2 | `cd workers && npm ci` が正常に完了済み | [ ] |
| D-3 | `npx wrangler dev` で手元の中継サーバーが起動することを確認済み | [ ] |
| D-4 | Xcodeでのビルド・シミュレータ起動を確認済み | [ ] |

> D-2〜D-4は、アプリ本体のコードが実装フェーズ（Phase 7）で完成したあとに行う項目。それより前の段階では、A〜Cまで（アカウント作成・キー発行・値の設定）を先に済ませておけば着手可能。

### ✅ 着手OKの条件

**製品コードの修正は設計承認後に行う。Cloudflare公開、Secrets登録、Bundle Identifier・Team変更、実機インストールは、それぞれの直前に値・影響・コマンドを示して明示承認を得る。**

---

## 1. Gemini APIキーの発行手順（Google AI Studio）

何のためにやるか：このアプリのAI対話・要約機能は、Googleの「Gemini」というAIを使う。そのAIを呼び出すための“合言葉”（APIキー）をここで発行する。

> Google AI Studioで新しいAuth keyを作成し、Workers側だけに登録する。制限のない旧Standard keyは流用しない。キーの現行仕様は実行直前にGoogle公式文書（`https://ai.google.dev/gemini-api/docs/api-key`）で確認する。値は会話、Git、ログへ出さない。

1. ブラウザ（Safari・Chromeなど）で `https://aistudio.google.com/apikey` を開く
   - 何のため：Gemini APIキーの発行・管理画面を開くため
2. 普段使っているGoogleアカウントでログインする（表示されない場合は自動的にログイン済みの状態で画面が開く）
3. 初回のみ、利用規約への同意画面が出るのでチェックを入れて「Continue」（続ける）をクリックする
   - 成功サイン：APIキーの管理画面（「API keys」という見出しのページ）が表示される
4. 画面右上（または画面中央）にある **「Create API key」** ボタンをクリックする
   - 何のため：新しいAPIキーを1つ発行するため
5. プロジェクトを選ぶ画面が出た場合は、初期状態で選ばれている「新しいプロジェクトを作成する」を選んだまま「Create API key」をクリックする
   - 特にこだわりがなければプロジェクト名は初期値のままでよい
6. 数秒待つと、Gemini APIキーの文字列が画面に表示される
   - 成功サイン：APIキーの文字列が表示され、隣にコピー用のアイコンがある
7. コピーアイコンをクリックしてAPIキーをコピーし、メモ帳など安全な場所に一時的に控えておく
   - この値は、後述の「2. Cloudflareアカウント作成・Workersセットアップ手順」の中で使う（`GEMINI_API_KEY` として設定する）

### うまくいかないとき
- 「Create API key」ボタンが見当たらない → 画面左側のメニューに「Get API key」という項目がないか確認し、そこからAPIキー管理画面に入り直す
- ログインしているのに規約同意画面が繰り返し出る → 一度ブラウザのタブを閉じて、`https://aistudio.google.com/apikey` に直接アクセスし直す

---

## 2. Cloudflareアカウント作成・Workersセットアップ手順

何のためにやるか：Gemini APIキーをiOSアプリの中に直接書き込むと、アプリを解析されたときにキーが漏れてしまう。そこで、iOSアプリとGemini APIの「中継役」となる無料のサーバー（Cloudflare Workers）を用意し、キーはそのサーバー側だけに保管する。

### 2.1 Cloudflareアカウントの作成

1. ブラウザで `https://dash.cloudflare.com/sign-up` を開く
   - 何のため：Cloudflareのアカウントを新規作成するため
2. メールアドレスとパスワードを入力し、「Sign Up」（サインアップ）ボタンをクリックする
   - 料金・カード要否は変更され得る。アカウント作成直前に登録画面とCloudflare公式のWorkers料金ページを確認する
3. 届いた確認メールのリンクをクリックしてメールアドレスを認証する
   - 成功サイン：Cloudflareのダッシュボード（管理画面のトップページ）が表示される

### 2.2 Node.jsのインストール確認

「Node.js」は、この後使う `wrangler`（Cloudflareの公式ツール）を動かすために必要な土台のソフト。

1. Macの「ターミナル」アプリを開く（Spotlight検索＝画面右上の虫眼鏡アイコンをクリックし、「ターミナル」と入力してEnterキーを押す）
2. ターミナルに以下を1行だけ貼り付けてEnterキーを押す

```bash
node -v
```

3. `v20.0.0` 以上のバージョン番号（例：`v20.11.0`）が表示されれば成功。何も表示されない、または「command not found」と出た場合は未インストールなので、`https://nodejs.org/` から「LTS」と書かれている方のインストーラーをダウンロードして実行し、再度 `node -v` を試す
   - 何のため：この後使う `wrangler`（バージョン4系）を動かすために、Cloudflare公式が対応バージョンとしている `Node.js 20.0.0以上` を必要とするため（出典：`https://developers.cloudflare.com/workers/wrangler/install-and-update/`）

### 2.3 プロジェクトのWorkersフォルダに移動する

1. ターミナルに以下を貼り付けてEnterキーを押す（`{プロジェクトのパス}` の部分は実際にMyBooksMemoフォルダを置いた場所に読み替える）

```bash
cd {プロジェクトのパス}/MyBooksMemo/workers
```

- 成功サイン：ターミナルの表示（プロンプト）が `.../MyBooksMemo/workers` のような表示に変わる
- ⚠️ `workers` フォルダの中身（`package.json` など）は、実装フェーズ（Phase 7）でコードが作成されたあとに存在するようになる。まだフォルダが存在しない場合は、このステップは実装完了後に行う

### 2.4 依存パッケージのインストール

```bash
npm ci
```

- 何のため：`wrangler` などこのプロジェクトに必要な部品一式をダウンロードするため
- 成功サイン：エラーメッセージなく処理が終わり、`workers` フォルダの中に `node_modules` というフォルダが新しくできる

### 2.5 Cloudflareアカウントとの連携（ログイン）

```bash
npx wrangler login
```

- 何のため：ここから先の `wrangler` コマンドが、自分のCloudflareアカウントを操作できるようにするため
- 実行するとブラウザが自動的に開き、Cloudflareの許可画面が表示される。「Allow」（許可する）をクリックする
- 成功サイン：ブラウザに「Successfully authorized」（認証に成功しました）のような画面が出て、ターミナルにも「Successfully logged in」と表示される

### 2.6 秘密情報未設定での初回公開

この操作はWorkerを外部公開する。実行直前に対象アカウント、Worker名、影響、実行コマンドを示して明示承認を得る。SecretsがないリクエストはGemini APIを呼び出さず失敗する（fail closed）。

```bash
npx wrangler deploy
```

出力に含まれるWorkers URLはログや会話へ転載せず、利用者が安全な場所へ直接控える。

2026-09-10にCloudflare OAuth認証と`workers.dev`への初回公開を完了した。認証ヘッダーなしの公開`POST /chat`はWorker固有JSONのHTTP 401を返し、認証ヘッダーがないリクエストを拒否することを確認している。

### 2.7 秘密の値をCloudflare Workersに登録する

次の各コマンドはWorkerの新バージョンを公開する。初回デプロイとは別に明示承認を得てから、ローカル端末の対話入力で登録する。値は画面共有、ログ、Git、会話へ出さない。

```bash
npx wrangler secret put GEMINI_API_KEY
npx wrangler secret put WORKERS_SHARED_SECRET
```

GeminiのAuth keyはGoogle AI Studioから直接入力する。共有シークレットはパスワードマネージャー等で安全に生成し、WorkersとiOSに同じ値を直接入力する。

```bash
npx wrangler secret list
```

この確認ではSecretsの名前と種類だけを扱い、値は表示しない。

2026-09-10に`GEMINI_API_KEY`と`WORKERS_SHARED_SECRET`を登録し、`wrangler secret list`で名前だけを確認した。新しいGemini Auth keyを作成して既存Workerの`GEMINI_API_KEY`を値非表示で差し替えた。今回のCLI標準入力経路では登録値不一致を再現したため、Cloudflare公式APIのSecret更新経路で同じ値を反映した。各更新によりWorkerの新バージョンが公開されている。値は表示・記録しない。

### 2.8 公開後の疎通確認

公開`/chat`・`/summarize`・`/advice`は、正しい共有シークレットでHTTP 200かつ非空応答を返すことを確認した。誤った共有シークレットではHTTP 401の`unauthorized`を返す。所有者iPhoneの実機画面でGemini応答の反映と通信失敗後の復旧・再試行を確認した。Workers URLと秘密値はコマンド履歴、ログ、報告に残さない。

### うまくいかないとき
- `npm ci` で大量のエラーが出る → `node -v` を再確認し、Node.jsのバージョンが20以上になっているか確認する
- `wrangler login` でブラウザが開かない → ターミナルに表示されたURLを手動でコピーしてブラウザに貼り付けて開く
- `wrangler deploy` で「Unauthorized」と出る → `npx wrangler login` を実行し直す
- 秘密の値を間違えて登録してしまった → 同じ `wrangler secret put` コマンドをもう一度実行すれば上書きできる（削除してから登録し直す必要はない）

---

## 3. Xcode側のシークレット設定手順

何のためにやるか：Cloudflare Workersで発行したURLと合言葉を、iOSアプリのコードに直接書き込まずにXcodeに教えるための作業。

### 3.1 設定ファイルの用意

1. Finder（Macのファイル管理アプリ）で `MyBooksMemo` フォルダを開く
2. `Secrets.xcconfig.example` というファイルを探し、コピー＆ペーストで複製する
3. 複製したファイルの名前を `Secrets.xcconfig` に変更する
   - 成功サイン：`MyBooksMemo` フォルダの中に `Secrets.xcconfig.example`（元のファイル）と `Secrets.xcconfig`（新しく作ったファイル）の2つが並んでいる

### 3.2 値の記入

1. `Secrets.xcconfig` をテキストエディタ（メモ帳アプリや、Xcode自体でも開ける）で開く
2. 中身を以下の形に書き換える

```
CLOUDFLARE_WORKERS_URL = https:/$()/mybooksmemo-workers.example.workers.dev
WORKERS_SHARED_SECRET = your-shared-secret-here
```

- `mybooksmemo-workers.example.workers.dev` の部分を、手順2.6で控えた自分の実際のURL（`https://` を除いた部分）に書き換える
- `your-shared-secret-here` の部分を、手順2.7で決めた共有シークレットに書き換える

> ⚠️ **URLの書き方に注意（`$()` を消さないこと）**
> `.xcconfig` というファイルの中では、`//`（スラッシュ2つ）が「ここから先はコメント（メモ書き）です」という意味になってしまう決まりがある。そのため `https://...` とそのまま書くと、`https:` から後ろが全部無視されてしまう。
> これを避けるため、`https:/$()/...` のように `/` と `/` の間に `$()`（何もしないおまじない）を挟んで書く。`$()` の部分は消さずにそのまま残すこと。
> 記入例：実際のURLが `https://mybooksmemo-workers.taro123.workers.dev` の場合 →
> `CLOUDFLARE_WORKERS_URL = https:/$()/mybooksmemo-workers.taro123.workers.dev`

3. ファイルを保存する

### 3.3 XcodeのBuild Settingsに設定する

1. Xcodeで `MyBooksMemo.xcodeproj` を開く
2. 画面左側のプロジェクトナビゲータ（ファイル一覧）の一番上にある、青いアイコンの `MyBooksMemo` をクリックする
3. 画面中央上部に表示される一覧（PROJECT／TARGETSの2種類がある）から、**PROJECTS側の「MyBooksMemo」**（TARGETS側ではない方）を選ぶ
4. 上部のタブから **「Info」** タブをクリックする
5. 下の方にある **「Configurations」** という項目を開く（矢印マークをクリックすると展開される）
6. 「Debug」の行にある「Based on Configuration File」の欄をクリックし、ドロップダウンから `Secrets` を選ぶ
7. 「Release」の行についても同様に `Secrets` を選ぶ
   - 成功サイン：Debug・Release両方の行に `Secrets` という設定ファイル名が表示されている

### うまくいかないとき
- ドロップダウンに `Secrets` という項目が出てこない → `Secrets.xcconfig` のファイル名が正確か（`.xcconfig.example` のままになっていないか）を確認し、Xcodeを一度再起動する
- 「Secrets.xcconfig」がプロジェクトナビゲータに表示されない → Finderでファイルを作っただけではXcodeに認識されない場合がある。プロジェクトナビゲータ上で右クリック→「Add Files to "MyBooksMemo"...」からファイルを追加する

---

## 4. ローカル開発・動作確認手順

> ⚠️ このセクションは、実装フェーズ（Phase 7）でiOSアプリ・Cloudflare Workers双方のコードが完成したあとに実施する。コードが存在しない段階では、ここから先は進められない。

### 4.1 Cloudflare Workersを手元で起動する

1. ターミナルで `workers` フォルダに移動する（すでにいる場合は不要）

```bash
cd {プロジェクトのパス}/MyBooksMemo/workers
```

2. `.dev.vars`（手元での確認用に、APIキーと合言葉を書いておくファイル）を用意する

```bash
cp .dev.vars.example .dev.vars
```

3. `.dev.vars` をテキストエディタで開き、以下の2行を実際の値に書き換えて保存する（`Secrets.xcconfig` に書いたのと同じ合言葉、手順1で発行したのと同じGemini APIキーを使う）

```
GEMINI_API_KEY=（手順1で発行したAPIキー）
WORKERS_SHARED_SECRET=（手順2.7で決めた合言葉）
```

- 何のため：`wrangler dev` で手元にサーバーを起動したときに、本番と同じ値を使ってテストできるようにするため
- ⚠️ このファイルは `.gitignore` の設定によりGitに記録されない。誤って人に見せたり公開リポジトリに載せたりしないよう、このファイルの取り扱いには注意する

4. 手元のサーバーを起動する

```bash
npx wrangler dev
```

- 成功サイン：ターミナルに `⎔ Starting local server...` のような表示のあと、`http://localhost:8787` というアドレスが表示され、そのまま待機状態になる（コマンドが終了せず動き続けている状態が正常）

5. 起動を確認できたら、別のターミナルのウィンドウを新しく開き、以下のコマンドで疎通確認（サーバーがちゃんと応答するかの確認）を行う

```bash
curl -i -X POST http://localhost:8787/chat \
  -H "Content-Type: application/json" \
  -H "X-Shared-Secret: （手順2.6で決めた合言葉）" \
  -d '{"bookTitle":"テスト","memoContent":"テストメモ","conversationHistory":[]}'
```

- 成功サイン：`HTTP/1.1 200 OK` のあとにGeminiが生成した質問文らしきテキストが返ってくる
- 合言葉をわざと間違えて同じコマンドを実行すると `HTTP/1.1 401` が返ってくることも確認しておくとよい（FR-06の認証チェックが正しく効いている証拠になる）

### 4.2 Xcodeでビルド・シミュレータ起動を確認する

1. Xcodeで `MyBooksMemo.xcodeproj` を開く
2. 画面上部中央のデバイス選択メニューで、iOS 17以上のシミュレータ（例：「iPhone 15」）を選ぶ
3. 画面左上の再生ボタン（▶）をクリックする、またはキーボードで `command + R` を押す
   - 何のため：アプリをビルド（コードを実際に動くアプリの形に変換すること）して、シミュレータ上で起動確認するため
4. しばらく待つとiOSシミュレータが自動的に立ち上がり、アプリが起動する
   - 成功サイン：本棚一覧画面（本の一覧が表示される画面。まだ何も登録していなければ「本を登録してください」といった空状態の表示）が表示される

### うまくいかないとき
- `curl` の結果が返ってこない・接続エラーになる → `wrangler dev` を実行しているターミナルがまだ起動したままか確認する（`Ctrl + C` で誤って止めていないか）
- Xcodeでビルドエラーが出る → エラーメッセージの中に `Secrets` や `CloudflareWorkersURL` という文言がないか確認する。あれば「3. Xcode側のシークレット設定手順」に抜けがある
- シミュレータが起動するがアプリがクラッシュする → Xcode下部のログ（コンソール）に `Config.swift` や `Info.plist` に関するエラーが出ていないか確認する

### 4.3 所有者iPhoneへの署名ビルド・インストール

2026-09-02〜03の実測では、所有者iPhoneをUSB、CoreDevice、XcodeのRun destinationで安定して列挙できた。明示的なUnsupported OSエラーはなく、証明書のOUとProvisioning ProfileのTeamIdentifierの一致を確認したうえで、自動署名のbuild-for-testing、インストール、起動をPASSした。Team IDは記録しない。

ローカル受入では、手入力による書籍登録、メモの再起動後の永続化、削除、オフライン時のエラー表示・クラッシュなし・データ維持、通信復旧後の再試行、USBとデバッガを外した通常起動をPASSした。WorkersとSecretsは公開・登録済みで、公開`/chat`・`/summarize`・`/advice`は正しい共有シークレットでHTTP 200かつ非空応答、誤った共有シークレットでHTTP 401を返すことを確認している。iOS側の`Secrets.xcconfig`を設定し、署名ビルド、上書きインストール、デバッガなし起動をPASSした。実機画面でGemini応答の反映と通信失敗後の復旧・再試行を確認し、総合判定は`PASS`とする。

別の端末または将来の再インストールでは、まずUSB接続を優先し、iPhoneのロック解除、Macの信頼、Developer Mode、XcodeのRun destinationへの安定した列挙を確認する。初期対応ではペアリング解除や端末設定変更を行わず、安定接続後に明示的なUnsupported OSエラーが出た場合だけ、必要なXcodeを再判定する。

Team選択、App ID・Provisioning Profile・端末登録の作成または更新、Developer Mode・信頼設定の変更、署名ビルド・インストールを行う直前には、次の影響を整理して明示承認を得る。

- 有料Apple Developer ProgramのTeam選択
- App IDとProvisioning Profileの作成・更新
- iPhoneのDeveloper Mode、端末登録、信頼設定
- Xcodeによる署名ビルド、インストール、起動

承認後の手順：

1. XcodeのSigning & CapabilitiesでAutomatically manage signingを有効にし、明示された有料Teamを選択する。複数の有料Teamが表示された場合は停止する
2. 承認済みBundle IdentifierがAppとTestsの両方で一致していることを確認する。App IDを登録できなければ別名を推測せずBLOCKEDとする
3. iPhoneをUSBまたは信頼済みワイヤレス接続し、Macを信頼する。iPhoneでDeveloper Modeを有効にする
4. XcodeのRun destinationで所有者iPhoneを選び、署名ビルド・インストール・起動を行う
5. デバッガを外してホーム画面から再起動する

実機受入では、書籍登録の1経路、メモ保存と再起動後の永続、削除、通信失敗時にクラッシュやデータ消失がなく復旧後に再試行できること、デバッガなしの通常起動、Gemini応答の反映、公開Workersでの401確認を完了した。

### 動作確認チェック

> requirements.mdの全FRに対応するケースを一覧にしている。上から順に試すことで、機能ひと通りの動作を確認できる。

| # | 対応FR | 確認内容 | 期待結果 |
|---|---|---|---|
| 1 | FR-01 | 本棚一覧画面の「＋」→スキャン画面で、実在する本のISBNバーコード（978または979で始まる13桁）をカメラに映す | 書誌情報確認画面に、その本のタイトル・著者・表紙（あれば）が自動表示される |
| 2 | FR-01（異常系） | ISBN以外のバーコード（例：食品のバーコード）をスキャン画面に映す | 「978または979で始まる13桁を読み取ってください」と表示され、スキャンが継続される |
| 3 | FR-01（異常系） | Wi-Fi・モバイル通信をすべてオフにした状態でISBNバーコードをスキャンする | 「インターネットに接続されていません。手入力で登録しますか？」と表示され、「手入力で登録する」ボタンが出る |
| 4 | FR-02 | 「手入力で登録する」からタイトルのみ入力して「登録する」をタップする | 本棚一覧画面に、著者「著者不明」として新しい本カードが追加される |
| 5 | FR-02（異常系） | 手入力フォームでタイトルを空欄のまま「登録する」をタップする | 「タイトルを入力してください」と赤字で表示され、登録されない |
| 6 | FR-03 | 登録済みの本の詳細画面で「今日のメモを書く」からメモ本文を入力して保存する | メモ一覧の先頭に、本日の日付のメモが追加表示される |
| 7 | FR-03 | 同じ本・同じ日に、もう一度「今日のメモを書く」を開いて内容を書き換えて保存する | 新しいメモが増えるのではなく、先ほどのメモの内容が上書きされる |
| 8 | FR-04 | メモ保存後の「AIと対話して深掘りする」で「はい」を選び、AIの質問に回答を送信する | AIからの質問がチャット画面に表示され、回答するたびに次の質問が返ってくる |
| 9 | FR-04（異常系） | 機内モードにしてからAI対話画面を開こうとする | 「インターネットに接続されていません」と表示され、「本詳細画面に戻る」ボタンのみ表示される |
| 10 | FR-05 | メモを1件以上記録した本の詳細画面で「要約」タブを開き、「要約を作成する」をタップする | ボタンがローディング表示になったあと、要約文と生成日時が表示される |
| 11 | FR-05（異常系） | メモを1件も記録していない本の「要約」タブを開く | 「要約を作成する」ボタンが押せない状態（非活性）で、「メモを記録すると要約を作成できます」と表示される |
| 12 | FR-07 | 本棚一覧画面で本カードを左にスワイプし「削除」→確認ダイアログで「削除する」をタップする | 確認ダイアログの通りの文言が表示されたあと、本棚一覧からその本のカードが消える |
| 13 | FR-07 | 本詳細画面でメモカードを左にスワイプし「削除」→確認ダイアログで「削除する」をタップする（事前にAI対話も行っておく） | そのメモがメモ一覧から消える。同じ日のAI対話ログも合わせて消えるが、要約タブの内容はそのまま残る |

---

## 要確認事項

- なし（本ドキュメント作成時点で、architecture.md・requirements.mdの内容と矛盾する点、および委譲プロンプトで判断がつかない点はなかった）
