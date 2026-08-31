# Codex Cloud task共通テンプレート

この文書はCloud taskの依頼文から明示的に参照する。
Cloudが自動的に読み込むことには依存しない。

## 1. 依頼時に埋める項目

```text
タスク種別: read-only / implementation / fix
期待する開始ブランチ: <GitHub上のブランチ名>
期待する開始コミットSHA: <40桁SHA。implementation / fixでは必須、read-onlyでは任意>
作業範囲: <読取対象または変更を許可する対象>
完了条件: <このtaskの完了条件>
```

`implementation`と`fix`では、開始ブランチと40桁SHAの両方を必ず指定する。
`read-only`ではSHAを省略できる。SHAを指定した場合はHEADとの一致を必須とする。
SHAを省略した場合は、期待ブランチのGit参照とHEADの一致を必須とする。

## 2. 変更前の強制ゲート

実作業やファイル変更の前に、次の順序で確認する。

1. 次の必須ファイルが存在し、読めることを確認する。
   - `AGENTS.md`
   - `progress.md`
   - `.codex/cloud-setup.md`
   - `.codex/cloud-task-template.md`
   - `.codex/flow.md`
2. `AGENTS.md`、`progress.md`、`.codex/cloud-setup.md`、
   `.codex/cloud-task-template.md`を読む。
3. `progress.md`から現在フェーズを特定し、`.codex/flow.md`は
   現在フェーズに必要なセクションだけを読む。
4. `git rev-parse HEAD`で実際の開始SHAを取得する。
5. `git branch --show-current`でCloud内の作業ブランチを取得する。
6. 期待する開始ブランチについて、`refs/heads/<branch>`と
   `refs/remotes/origin/<branch>`の有無を確認する。
7. 期待SHAが指定されている場合は、HEADとの一致を必須とする。
   ブランチ参照が存在する場合は、その参照と期待SHAの一致も必須とする。
   ブランチ参照が存在しない場合は、HEADと期待SHAが一致していれば
   参照不在を記録して継続する。
8. `read-only`で期待SHAが省略されている場合は、ブランチ参照の取得と、
   その参照とHEADの一致を必須とする。

Cloud内部の作業ブランチ名は期待する開始ブランチと別名でもよい。
実測した名前を最終報告へ記録する。

次のいずれかに該当した場合は、変更コマンドを実行せず`BLOCKED`として停止する。

- 必須ファイルが存在しない、または読めない
- `implementation`または`fix`で開始ブランチか40桁SHAが未指定
- 期待SHAが指定され、実際のHEADと一致しない
- 期待ブランチの参照が存在し、その参照と期待SHAまたはHEADが一致しない
- `read-only`で期待SHAを省略し、期待ブランチの参照を取得できない

## 3. Cloudで禁止する操作

- ファイル変更（`read-only`の場合）
- `git push`、PR作成、マージ
- 外部API、本番データへの接続
- 本番デプロイ、本番DBの変更
- Codex Cloud environment、環境変数、Secretsの作成・設定変更
- 依頼範囲外のファイル変更や依存追加

Cloud上のLinuxによる構造確認、静的確認、Git差分確認は、プロジェクトの標準テスト、
実機・実環境確認、外部連携確認の代替にしない。

## 4. 最終報告の必須形式

```text
判定: PASS / LIMITED / BLOCKED

読み込んだ指示:
- AGENTS.md
- progress.md
- .codex/cloud-setup.md
- .codex/cloud-task-template.md
- .codex/flow.md: <読んだ現在フェーズのセクション>

開始点:
- 期待する開始ブランチ:
- 期待する開始SHA:
- 実際の開始SHA:
- 期待ブランチの参照: <local / origin / 参照不在>
- 期待ブランチ参照のSHA: <取得値 / 取得不能>
- Cloud内の作業ブランチ:

実行コマンド:
- <実際に実行したコマンド>

結果:
- <各完了条件の結果>
- Git差分: なし / あり

未検証範囲:
- <Cloudで実行していない標準テスト>
- <実機・実環境・外部連携の確認>
```

`read-only`はGit差分がない場合だけ`PASS`にできる。
Cloudで実行できない検証は、未検証範囲として明記する。
