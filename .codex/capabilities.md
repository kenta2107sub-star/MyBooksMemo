# スキル・Codex機能一覧

## モデルとカスタムエージェント

| エージェント | モデル | 主な担当 |
|---|---|---|
| `mock-builder` / `implementer` / `debugger` / `code-reviewer` / `security-reviewer` | `gpt-5.6-sol`・high | 複雑な生成、実装、原因分析、レビュー |
| `researcher` / `design-writer` / `detailed-designer` | `gpt-5.6-terra`・high | 調査、設計書作成、詳細設計 |
| `consistency-checker` / `tester` / `deployer` | `gpt-5.6-terra`・high | 整合性確認、テスト、承認済みデプロイ |

定義は `.codex/agents/*.toml` に置く。
メインは `gpt-5.6-sol`・high を使う。

## フェーズ別の必須スキル

| スキル | 用途 | 使用時期 |
|---|---|---|
| `requirements-writer` | 要件定義書 | Phase 2 |
| `architecture-writer` | アーキテクチャ設計書 | Phase 2 |
| `setup-writer` | セットアップガイド | Phase 2 |
| `business-writer` | ビジネス・運用文書 | Phase 2 |
| `basic-design-writer` | 基本設計書 | Phase 2 |
| `mock-frontend-design` | UIモック | Phase 3〜4 |
| `detailed-design-writer` | 詳細設計書 | Phase 5 |
| `consistency-checker` | 設計書とモックの整合性 | Phase 6 |
| `implementation-runner` | 本実装 | Phase 7 Step A |
| `testing-runner` | 総合テスト | Phase 7 Step B |
| `debug-runner` | バグ調査・修正 | Phase 7 Step C |
| `code-reviewer` | コードレビュー | Phase 7 Step D |
| `deployment-runner` | サーバーデプロイ | Phase 8 |
| `readme-writer` → `humanizer-ja` | README 作成・更新 | Phase 8、運用中の更新時 |

## Codex Security

| 機能 | 用途 | 使用時期 |
|---|---|---|
| Codex Security Plugin | 脅威モデル、到達可能な攻撃経路、検証根拠、修正案を含む深いセキュリティレビュー | Phase 7 Step F、運用中のセキュリティトリガー該当時 |

Codex Security は `security-and-hardening` スキルや `code-reviewer` の代替ではない。
通常テストとコードレビューを通過した後の独立したセキュリティゲートとして使用する。

Plugin はプロジェクトローカルのスキルやカスタムエージェントではない。
Phase 0 で利用可否を確認し、利用できない場合は `security-reviewer` と
`security-and-hardening` を使うフォールバックレビューへ切り替える。

## 横断スキル

| スキル | 使用条件 |
|---|---|
| `pre-implementation-check` | 新機能、新アプローチ、外部API、OS制約を扱う前 |
| `debugging-approach` | 原因が証拠で確定していない不具合の修正前 |
| `refactoring-runner` | 動作を変えず構造を改善するとき |
| `code-simplification` | 複雑さを減らす必要があるとき |
| `security-and-hardening` | 認証、入力、秘密情報、外部連携を扱うとき |
| `performance-optimization` | 計測でボトルネックを確認した後 |
| `ci-cd-and-automation` | CI/CDを構築・変更するとき |
| `observability-and-instrumentation` | 本番ログ、メトリクス、アラートを整備するとき |
| `ui-ux-pro-max` | Web・モバイルのUI設計と実装時 |
| `imagegen` | 写真、イラスト、テクスチャ等のビットマップ素材が必要なとき |

## 調査・ドキュメント確認

- 外部サービスの仕様・料金・制限は、Web検索で公式情報を確認する
- OpenAI・Codex の仕様は `openai-docs` を使う
- ライブラリとSDKは公式ドキュメントを優先する
- 技術的実現可能性は `pre-implementation-check` で最小検証する

## Codex Cloud

- Cloud environmentの仕様確認には`openai-docs`を使い、公式文書を毎回確認する
- サインイン済みのCloud設定画面を操作できる場合は、アプリ内ブラウザを使う
- `.codex/cloud-setup.md`へ設定意図と実測結果を記録し、秘密値は保存しない
- UIの設定保存とCloud taskの実行検証を分け、task内の実測値を最終証拠にする

## 実行可能成果物の表示・検証

- ユーザー提示前は `.codex/flow.md` の「ユーザー提示前の事前検証ゲート」を必ず実施する
- Web UIはアプリ内ブラウザで開き、375pxとデスクトップ幅でクリック・入力・スクロール・
  画面遷移を実行し、状態変化、コンソール、操作前後のスクリーンショットを確認する
- Chrome Extensionはテスト用ブラウザプロファイルで popup / options を操作し、
  通常ページとして確認できる画面はアプリ内ブラウザも使用する
- モバイル・ネイティブUIは、現在のPCで利用可能かつ公式対応するプレビュー、
  エミュレータ、シミュレータ、実機の順で最も適切な環境を使い、タップ・入力・遷移・
  ダイアログ等を操作して状態変化を確認する
- デスクトップUIはローカル実行環境でクリック・入力・スクロール・遷移・ダイアログを操作する
- API・Webhook・Botは隔離したテスト環境で正常・空・不正入力と失敗条件を実行し、
  CLIはクリーンなシェルと一時ディレクトリで正常・空・不正引数と失敗条件を実行する
- Build iOS Apps / XcodeBuildMCP はOS・Xcodeの公式要件を満たす場合だけ使い、固定要件にしない
- 表示、起動、静的なコード確認だけでは `PASS` にせず、操作シナリオ、期待結果、実測結果、
  スクリーンショットまたはログを記録する。操作できない範囲は理由と代替確認を明記して `LIMITED` とする
- 会話内の図解が理解を明確にする場合だけ `visualize` を使う

## スキルの配置

Codex公式のリポジトリローカル配置は `.agents/skills/{スキル名}/SKILL.md`。
ユーザー共通スキルは `$HOME/.agents/skills/{スキル名}/SKILL.md` を基本とする。

この環境では `$CODEX_HOME/skills/{スキル名}/SKILL.md` に導入済みのスキルも読み込まれる。
新規プロジェクト固有のスキルだけを `.agents/skills/` に置き、共通スキルを複製しない。
