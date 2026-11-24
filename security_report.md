# MyBooksMemo セキュリティレビュー

実施日：2026-09-08  
最終更新：2026-09-10
実行方式：Codex Security Plugin 標準リポジトリ再スキャン  
対象：現行working tree全体 101ファイル  
Coverage：`complete`

## 判定

- 要修正：0件
- 受容済み残余リスク：1件（Low）
- 認証先行修正：解消確認済み
- npm監査：開発依存High 4件、本番依存0件（期限付きで受容）

公開Workersは誤った共有シークレットの401と、
正しい共有シークレットによる3ルートの正常応答を確認済み。
Cloudflare側の要求量制限は検査していない。
秘密情報は一致・非混入だけを検査し、値を出力・記録していない。

## 解消確認

### 未認証リクエストの本文処理

- 旧判定：Low
- 現在：解消済み
- 対象：`workers/src/routes/chat.ts`、`summarize.ts`、`advice.ts`
- 根拠：3ルートとも共有値の認証を本文読取・JSON解析・入力検証より先に実行する。
- 回帰証拠：認証欠落・不一致の計6ケースで本文未読、Gemini未呼出、401を確認した。
- 公開証拠：誤った共有シークレットの公開`POST /chat`がWorker固有JSONのHTTP 401を返し、正しい値では3ルートがHTTP 200を返した。

## 受容済み残余リスク

### iOSバンドルへ展開される静的共有値

- 重大度：Low
- 確信度：High
- 対象：`MyBooksMemo/Info.plist:32`、`MyBooksMemo/Services/CloudflareWorkersClient.swift:88`、`workers/src/lib/auth.ts:14`
- 根拠：共有値はアプリの`Info.plist`へ展開され、3つのWorker経路の認可条件として使われる。
- 影響：配布済みアプリバンドルを取得・解析できる者は、値を再利用してGemini機能を呼び出せる。
- 緩和要因：所有者iPhoneへの直接配布に限定され、Gemini APIキーやローカル読書データは直接露出しない。
- 判断：現在の配布範囲ではユーザー承認済みの残余リスクとして受容する。
- 後続条件：漏えい時は両側の値をローテーションする。配布範囲を広げる前に、端末ごとに失効可能な短命トークン等へ認証モデルを変更する。

## 問題なしと確認した範囲

- Workersの認証順序、入力上限、Gemini未呼出制御、固定Gemini endpoint
- Gemini応答の形式・空文字・20,000 Unicodeコードポイント上限とSwiftUI `Text`表示
- NDLの固定HTTPSホスト、ISBN形式制約、XML処理、書影取得
- SwiftDataの単一利用者ローカル保存、確認付き削除、カメラ権限
- APIログのpath・status限定、秘密値パターン、テストのdummy値・mock利用
- 開発hookの固定argv実行

## npm監査の追加確認

- 実施日：2026-09-10
- `npm audit`：High 4件、Critical 0件
- `npm audit --omit=dev`：Highを含む脆弱性0件
- 到達経路：`@cloudflare/vitest-plugin`・`miniflare`・`wrangler`から`sharp 0.35.2`
- 影響判定：開発・テスト・デプロイ用のツールチェーンであり、公開Workerの本番依存には含まれない
- 対応：強制修正、依存バージョンの後退、`sharp`の手動overrideは行わない
- 再確認：Cloudflare側が`sharp 0.35.4`以降を採用した時点、または2026-10-10のいずれか早い方

## 本番Secretsの追加確認

- 新しいGemini Auth keyはCloudflare Workers側だけへ登録し、iOS設定・ソース・Gitへ保存していない
- `Secrets.xcconfig`はGit無視対象で、追跡されていない
- 実際のWorkers URLと共有シークレットはGit追跡ファイルに存在しない
- Gemini APIキー形式の値はGit追跡ファイルに存在しない
- 生成済みiOSアプリバンドルに`GEMINI_API_KEY`は存在しない
- 秘密値を扱った直後にクリップボードを消去し、現在の内容も秘密値ではないことを確認した

## 制約

- TACアクセスは`not_granted`だったが、助言情報でありスキャン自体は完了した。
- 独立focused investigatorは利用上限で停止したため、同じ調査packetを親側で静的確認した。
- 公開状態、実効Secrets、Gemini実疎通、誤った共有シークレットの401は確認済み。WAF・quotaは未確認のまま残した。

## Codex Security成果物

- `report.md`、`scan-manifest.json`、`findings.json`、`coverage.json`を生成・seal済み
- Finding：Low 1件
- Token usage：10,555,648（Codex Security計測値、5 threads合計）
