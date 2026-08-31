# MyBooksMemo Codex Cloudセットアップ

## 状態

`手順作成済み / GitHub未接続 / environment未作成 / Cloud未検証`

この文書はCodex Cloud environmentへ自動適用される設定ファイルではない。
ユーザーがCloud UIへ設定する値と、初回smoke taskの検証手順を記録する。

## 対象

- リポジトリ：`kenta2107sub-star/MyBooksMemo`
- 既定ブランチ：`main`
- 前提コミット：この文書を含むローカルコミット。Cloud利用前にPushし、40桁SHAを確認する
- Cloud対象：`workers/`のCloudflare Workers実装とテスト
- Cloud対象外：Xcodeを必要とするiOSビルド、Simulator、実機検証

## ランタイム

- Node.js：22系（22.12以上を推奨）
- package manager：npm（`workers/package-lock.json`を使用）
- 根拠：`workers/package-lock.json`内のWrangler、Vitest、Vite等がNode.js 22系を要求する

READMEにはNode.js 20以上とあるが、Cloudではlockfileの厳しい条件を優先する。
Cloud UIの選択値とtask内の`node --version`実測値は分けて記録する。

## Setup方式

Manual setupを使用する。Swift/iOSとNode.jsのmixedリポジトリであり、
Node.jsのlockfileがリポジトリ直下ではなく`workers/`にあるためである。

Environment settingsのsetup script：

```bash
set -euo pipefail
cd workers
npm ci
```

## Maintenance script

cached container再開時もlockfileと依存を一致させる。

```bash
set -euo pipefail
cd workers
npm ci
```

## 環境変数とSecrets

Cloudのsmoke taskとWorkers単体テストに環境変数・Secretsは不要である。
テストコードはダミー値とmockを使用し、外部APIへ接続しない。

次の本番値はCloud environmentへ登録せず、agentへ渡さない。

- `GEMINI_API_KEY`
- `WORKERS_SHARED_SECRET`
- `CLOUDFLARE_WORKERS_URL`

private registry用のSetup用Secretも不要である。

## Agent internet access

Agent phaseはOffを推奨する。依存導入はsetup scriptのinternet accessだけを使う。
smoke taskは外部API、本番データ、Cloudflare本番環境へ接続しない。

## 初回Cloud smoke task

`.codex/cloud-task-template.md`を明示参照し、次のpromptを使う。
`<Push後の40桁SHA>`はCloudから参照できる実際のコミットへ置き換える。

```text
タスク種別: read-only
期待する開始ブランチ: main
期待する開始コミットSHA: <Push後の40桁SHA>
作業範囲: MyBooksMemoのCloud環境とWorkers検証。ファイル変更は禁止。
完了条件: 指示読込、開始点一致、Node/npm実測、Workers typecheck/test、Git差分なし。

最初にAGENTS.md、progress.md、.codex/cloud-setup.md、
.codex/cloud-task-template.mdを読み、現在フェーズに必要な
.codex/flow.mdのセクションだけを読んでください。

git rev-parse HEADとgit branch --show-currentを実行し、
期待する開始ブランチと期待する開始コミットSHAを照合してください。
期待ブランチ参照が不在でもHEADと期待SHAが一致する場合は、
参照不在を記録して継続してください。

次を実行してください。
- node --version
- npm --version
- cd workers && npm run typecheck
- cd workers && npm test
- git status --short --branch
- git diff --check
- git diff --exit-code

必須文書不足・読取不能、HEAD不一致、開始点検証失敗では
ファイル変更前にBLOCKEDとして停止してください。
ファイル変更、Push、PR、外部API、本番操作、Cloud environment変更は禁止です。

最終報告には、読み込んだ指示、実際の開始SHA、Cloud内の作業ブランチ、
実行コマンド、各結果、Git差分、未検証範囲を記載してください。
Linuxでは実行できないXcode・Simulator・実機検証を未検証範囲へ含めてください。
```

## Cloud UIチェックリスト

- [ ] Codexへサインインし、GitHubの対象リポジトリへのアクセスを許可する
- [ ] MyBooksMemo用environmentを作成する
- [ ] Node.js 22系を選択する
- [ ] setup scriptとmaintenance scriptを登録する
- [ ] 環境変数とSecretsを登録しないことを確認する
- [ ] Agent internet accessをOffにする
- [ ] この文書を含むPush済み`main`の40桁SHAを取得する
- [ ] 上記read-only smoke taskを実行する
- [ ] task結果とGitHub remoteに意図しないPush・PRがないことを確認する

## 未確認事項と切り分け

- Cloud UIのランタイム選択値と実測Node.jsバージョンは未確認
- Cloudでの`npm ci`、typecheck、Workers testは未実行
- Xcode、iOS Simulator、実機、カメラ、SwiftDataの動作はCloudでは確認しない
- 外部API、Gemini、国立国会図書館、Cloudflare本番接続はsmoke taskの対象外
- setup失敗時はNode.js実測、`npm ci`のログ、lockfile整合性の順で確認する
- test失敗時はtypecheckとVitestを分け、Cloud固有か製品コード由来かを切り分ける

## 公式資料

- [Codex cloud](https://learn.chatgpt.com/docs/cloud)
- [Cloud environments](https://learn.chatgpt.com/docs/environments/cloud-environment)
