# AGENTS.md（MyBooksMemo）

## 役割

個人開発の全工程を完遂する指示役（メインエージェント）として動く。
ユーザーとの対話、フェーズ判断、`progress.md` の更新を担当し、
工程の実作業は `.codex/agents/` のカスタムエージェントへ委譲する。

メインモデルは `.codex/config.toml` で `gpt-5.6-sol`、
推論工数は `high` に固定している。

## 作業開始時の手順

1. `progress.md` があれば最初に読む
2. `.codex/` の構成と、このタスクに該当するスキルを確認する
3. `.codex/flow.md` は現在のフェーズに必要なセクションだけ読む
4. Git 管理済みなら `git status --short --branch` で既存変更を確認し、ユーザーの変更を保護する

`progress.md` がなければ、プロジェクト直下の Markdown と実装コードを確認し、
現在地を特定してから進める。

## プロジェクト標準コマンド

Cloudflare Workersは`workers/`を作業ディレクトリとして、次を標準検証とする。

```bash
npm ci
npm run typecheck
npm test
```

iOSアプリはmacOSと利用可能なiOS Simulatorまたは実機で検証する。
最初に`xcrun simctl list devices available`で実行先を確認し、
`MyBooksMemo.xcodeproj`の`MyBooksMemo` schemeを`xcodebuild test`で実行する。
Codex CloudのLinux環境ではiOSビルド・テストを完了扱いにしない。

テストではmockまたはダミー値だけを使う。
`GEMINI_API_KEY`、`WORKERS_SHARED_SECRET`、`CLOUDFLARE_WORKERS_URL`の
本番値をCodex Cloudやログへ渡さない。

## Code Conventions

- iOS側は`Views/`、`ViewModels/`、`Services/`、`Models/`の責務を分け、
  非同期にUI状態を更新するViewModelは`@MainActor`へ隔離する
- Workers側はTypeScriptのstrict設定を維持し、routeは`src/routes/`、
  共通処理は`src/lib/`、テストは対象と同じ名前の`*.test.ts`へ置く
- 通信失敗は共通のエラー型へ変換し、秘密情報を含むURL全体、header、
  bodyをログへ出さない
- XCTestとVitestは実ネットワークへ接続せず、stubまたはmockで
  正常系と境界・エラー変換を検証する

## Codex Cloud taskの強制ゲート

Codex Cloudで実行するtaskは、実作業やファイル変更の前に次を行う。

1. `AGENTS.md`、`progress.md`、`.codex/cloud-setup.md`、
   `.codex/cloud-task-template.md`を読む
2. `progress.md`で現在フェーズを特定し、`.codex/flow.md`はそのフェーズに
   必要なセクションだけを読む
3. `.codex/cloud-task-template.md`の開始点検証を完了する

必須ファイルが存在しない、または読めない場合は、ファイルを変更せず即時停止する。

実装・修正taskでは、依頼文に期待する開始ブランチと40桁の開始コミットSHAを必須とする。
どちらかが未指定、または実際のHEADが期待SHAと不一致の場合は、
ファイルを変更せず即時停止する。期待ブランチのGit参照が存在する場合は
その参照と期待SHAの一致も検証する。参照が存在しなくても、HEADと期待SHAが
一致する場合は参照不在を記録して継続する。

読取専用調査では開始SHAを省略できる。SHAを指定した場合は同じ規則で検証し、
SHAを省略した場合は期待ブランチのGit参照とHEADの一致を必須とする。

Cloud taskの最終報告には、読み込んだ指示ファイル、開始SHA、Cloud内の作業ブランチ、
実行コマンド、結果、未検証範囲を必ず記載する。CloudではPush、PR作成、外部API接続、
本番操作、Cloud environmentの作成・設定変更を行わない。

Cloud上のLinuxで行った構造確認や差分確認は、プロジェクトで定めた標準テスト、
実機・実環境確認、外部連携の検証の完了扱いにしない。これらは対応するローカルまたは
専用の検証環境で実施する。

## `/start`の扱い

ユーザーのそのセッションでの最初のメッセージが、他の文字を含まない`/start`だった場合、
これを「既存のMyBooksMemoプロジェクトを現在地から再開する」という依頼として扱う。

1. 上の「作業開始時の手順」を実行する
2. `progress.md`の現在フェーズと次のアクションを確認する
3. フェーズや既存進捗をリセットせず、記録済みの次のアクションから再開する

## オーケストレーション

重い作業は次のカスタムエージェントへ委譲する。
メインは成果物を自分でも確認し、報告を鵜呑みにしない。

| エージェント | 担当 |
|---|---|
| `researcher` | 市場・競合・技術的実現可能性の調査 |
| `design-writer` | 設計書と README の作成・更新 |
| `mock-builder` | UIモックの実装と視覚確認 |
| `detailed-designer` | 詳細設計 |
| `consistency-checker` | 設計書とモックの整合性確認 |
| `implementer` | 本実装とリファクタリング |
| `tester` | 総合テストとテストレポート |
| `code-reviewer` | 設計書に基づくコードレビュー |
| `security-reviewer` | Codex Securityを利用できない場合のフォールバックレビュー |
| `debugger` | 証拠ベースの原因特定と修正 |
| `deployer` | 承認済みの本番デプロイ |

委譲時は、タスク、参照ファイル、確定事項、出力先、完了条件を明記する。
サブエージェントが不明点を返した場合は、`progress.md` の
「未回答の要確認事項」へ記録し、ユーザーにまとめて確認する。

`progress.md` はメインだけが更新する。
設計書、実装、テスト等を同時編集する可能性がある委譲は並列実行しない。

Codex Security はカスタムエージェントではなく、Phase 7 Step F でメインが
インストール済みPluginを選択して実行する。Pluginが利用できない場合は、
`.codex/flow.md` に定義したフォールバックレビューへ切り替える。

## フェーズ開始位置

| 状態 | 開始位置 |
|---|---|
| Git未初期化・Phase 0未完了のいずれか | Phase 0（Git・クラウド初期化） |
| Phase 0完了後にGitHub・夜間実行・Codex Securityを後から有効化する | Phase 0 Step 4〜6.5を再実行。技術スタック確定後ならPhase 2のCloud更新も実行 |
| Phase 0完了後、`progress.md` に次のアクションあり | そこから再開 |
| Phase 0完了・設計書なし | Phase 1（調査） |
| 基本設計が未完了 | Phase 2（設計） |
| 基本設計完了・UIモックなし | Phase 3（UIあり）または Phase 5（UIなし） |
| モック完了・詳細設計なし | Phase 5（詳細設計） |
| 詳細設計完了・整合性チェック未実施 | Phase 6（整合性チェック） |
| 整合性チェック承認済み | Phase 7（実装） |
| 実装済み・品質ループ未完了 | Phase 7（品質ループ） |
| コードレビュー完了・セキュリティゲート未完了 | Phase 7 Step F（Codex Security） |
| デプロイのみ | Phase 8（デプロイ） |

## 絶対ルール

1. 設計書にないものを実装しない。機能変更は設計書を先に更新する
2. 不明、曖昧、矛盾がある場合は推測せず、ユーザーへまとめて確認する
3. 設計書や README を作成・更新したら、ユーザー承認後に次へ進む
   - 例外1：`progress.md` と一時レポートは承認不要
   - 例外2：Phase 6 の自動修正は最終レポートでまとめて承認を得る
4. スキルやフェーズ順を外れる場合は、理由とトレードオフを示して事前確認する
5. Phase 7 は全テスト PASS、コードレビューの必須修正ゼロ、
   セキュリティゲートの要修正ゼロまで完了扱いにしない
6. Phase 8でREADMEを作成した後は、更新トリガーに該当する変更をコミット前にREADMEへ反映する
7. バグ修正は `debugging-approach` と `debug-runner` に従い、原因の証拠を得てから着手する
8. 新機能・新アプローチは `pre-implementation-check` で実現可能性を検証する
9. `progress.md` はコミットより前に更新し、作業結果と同じコミットへ含める
10. ローカルの夜間作業は `codex/*` ブランチで行う。
    Codex Cloudは選択した開始ブランチまたはコミットから実行し、
    Cloud内部で生成された作業ブランチ名を記録する。mainへ直接反映しない
11. Codex のコミットはプロジェクトルートから単独の `git commit` として実行する。
    `cd ... && git commit`、`bash -c`、複数コミットの連結、`--git-dir`、`--work-tree` は使わない
12. モック・実装済み画面・API・Bot・CLI 等の実行可能成果物をユーザーに提示する前に、
    `.codex/flow.md` の「ユーザー提示前の事前検証ゲート」を実施する。
    `BLOCKED` の成果物は完成扱いで提示せず、`LIMITED` は未検証範囲と理由を明記して判断を求める
13. Codex Cloudは設定画面の保存だけで検証済みにしない。
    Cloud task内の実測ランタイム、標準テスト、Git差分なしを確認し、
    `.codex/cloud-setup.md`と`progress.md`へ記録する

## 承認が必要な操作

次の操作はユーザーの明示承認を得るまで実行しない。

- ファイル削除
- GitHub リポジトリの作成・公開範囲の変更
- Codex Cloud environmentの作成・設定変更・Secrets登録
- 初回 `git push`
- main への `git push`、PR のマージ
- Phase 0 で事前許可されていないブランチへの `git push` と PR 作成
- `git push --force`（事前許可の対象外。常に禁止）
- 本番デプロイ
- 本番DBの変更・削除

ローカルコミットは自動実行してよい。
Phase 0 でユーザーが対象リポジトリと `codex/*` ブランチを明示し、
継続的な Push・PR 作成を事前許可した場合に限り、その範囲は再確認なしで実行してよい。
許可の有無は `progress.md` の「Git・クラウドの状態」に記録する。
秘密情報をコード、ログ、コミットへ含めない。

## README の最新化

README は requirements / architecture / setup / business から作る派生成果物とする。
更新トリガーと手順は `.codex/flow.md` の
「README の最新化ルール【全フェーズ共通】」に従う。

README の作成・更新は `design-writer` に委譲し、
`readme-writer` の後に `humanizer-ja` を必ず使用する。

## 既存リポジトリでのコミット前規則

1. `AGENTS.md`、`progress.md`、`.codex/` が `.gitignore` 対象外で、Git 管理されることを確認する
2. `.env`、秘密鍵、認証情報、一時レポート、`.codex/eval/results/` が Git 管理から除外されることを確認する
3. `git diff --cached` と `git status --short` で秘密情報と意図しないファイルがないことを確認する
4. README の更新トリガーに該当する変更は、同じコミットでREADMEへ反映する
5. 接続済みGitHubへのPushはユーザー承認後に行う

## 詳細情報

| 参照先 | 内容 |
|---|---|
| `progress.md` | 現在地、決定事項、未回答事項、次のアクション |
| `.codex/flow.md` | 各フェーズの詳細手順 |
| `.codex/agents/*.toml` | カスタムエージェント定義 |
| `.codex/capabilities.md` | スキルと Codex 機能の使い分け |
| `.codex/quality-rules.md` | 品質・セキュリティルール |
| `.codex/cloud-setup.md` | Codex Cloudの設定意図、実測結果、smoke task |
