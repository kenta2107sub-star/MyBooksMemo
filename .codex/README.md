# MyBooksMemo Codex運用ファイル

このディレクトリは、個人開発フローを Codex で実行するためのプロジェクト設定です。

- `config.toml`：モデルとサブエージェントの設定
- `agents/`：工程別カスタムエージェント
- `hooks.json` / `hooks/`：progress.md と README の更新漏れ防止
- `flow.md`：Phase 0〜8 と運用フェーズの手順
- `capabilities.md`：利用するスキルと Codex 機能
- `quality-rules.md`：品質・セキュリティ規則
- `cloud-setup.md`：Codex Cloudの設定内容と実測結果

## ユーザー提示前の事前検証

モック、実装済み画面、API、Bot、CLI等の実行可能成果物は、ユーザーへ提示する前に
`flow.md` の「ユーザー提示前の事前検証ゲート」を通す。
Webブラウザだけに限定せず、利用可能なプレビュー、シミュレータ、隔離したテスト環境、
クリーンなシェル等をプロジェクトタイプに応じて選び、`PASS / LIMITED / BLOCKED` を判定する。

## 利用開始

1. CodexでMyBooksMemoフォルダを開く
2. プロジェクトローカル設定とhooksの信頼確認が表示されたら、内容を読んで承認する
3. 新しいセッションの最初のメッセージとして、`/start`だけを送信する
4. `progress.md`に記録された現在地と次のアクションから再開する

`/start`はMyBooksMemoの再開キーワードである。
受け取ったCodexは`AGENTS.md`に従い、既存の進捗をリセットせず再開する。

プロジェクトを信頼しない場合、`.codex/config.toml`、カスタムエージェント、
プロジェクトローカル hooks は読み込まれません。

## Codex Security

Phase 0 で Codex Security Plugin の利用可否を確認し、実行方式を `progress.md` に記録する。
初回リリース前は Phase 7 でコードベース全体をスキャンする。
Plugin が利用できない場合も開発を止めず、専用のフォールバックレビューを実施する。

Plugin はこのリポジトリへ同梱されるものではなく、Codex側でインストールする機能である。
利用開始時は [OpenAI公式のCodex Security Plugin手順](https://openai.com/daybreak/codex-security-plugin/) を確認する。

## Git・Codex Cloud・worktree

`AGENTS.md`、`progress.md`、`.codex/` は Git 管理する。
Codex Cloud がプロジェクト固有の指示と進捗を読み、worktree でも同じフローを再現するために必要となる。

このプロジェクトは既存のGitHubリポジトリへ`origin`で接続済みである。
mainへのPushはユーザーの明示承認後に行う。`.env`、認証情報、秘密鍵、
一時レポート、`.codex/eval/results/`は`.gitignore`で除外する。

Codex Cloudを使う場合は、GitHubアクセスとenvironmentをユーザー承認後に設定する。
具体的なNode.jsバージョン、setup script、maintenance script、Secretsを渡さない方針、
Agent internet access、smoke taskは`.codex/cloud-setup.md`に記載する。

Cloud設定画面のランタイム選択値と、task内の実行値は分けて記録する。
設定保存だけでは`Cloud検証済み`にせず、実測バージョン、標準テスト、Git差分なしを確認する。
環境変数はtask全体で利用できる一方、Secretsはsetup scriptでのみ利用できるため、
本番資格情報を通常の環境変数へ移さない。

ローカルの夜間作業は main ではなく `codex/*` ブランチで行う。
Codex Cloudは選択した開始ブランチまたはコミットから実行し、Cloudが生成した作業ブランチから
PRを作成してレビューする。どちらもmainへ直接反映しない。
`codex/*` への Push と PR 作成を無人実行するには、Phase 0 でユーザーの継続許可を得て
`progress.md` に記録しておく。main への Push・マージ・本番デプロイは継続許可の対象外とする。

ローカル Scheduled task を使う場合は、Mac の電源とデスクトップアプリを起動したままにし、
未完了作業との衝突を避けるため専用 worktree を使用する。
