# PDCA CLI - AI向けガイド

## このツールについて
プログラミングスクール受講生の日次学習報告(PDCA)を送信するCLIツール。
学習計画の設定、週次目標の管理、日次報告の作成ができる。

## 典型的な利用フロー
1. `bin/pdca plan setup` で学習計画を設定
2. `bin/pdca goal create` で週次目標を設定（学習計画から選択）
3. `bin/pdca report create` で日次報告を作成

## 主要コマンド

### 学習計画
```bash
# 学習計画の設定
bin/pdca plan setup --name "コース名" --categories "カテゴリ1" "カテゴリ2" --json

# 学習計画の確認
bin/pdca plan show --json

# カテゴリ追加
bin/pdca plan add --name "新カテゴリ" --hours 10 --json
```

### 週次目標
```bash
# 学習計画のカテゴリから選んで目標作成
bin/pdca goal create --category_ids 40 41 --json

# 自由入力で目標作成
bin/pdca goal create --items "目標1" "目標2" --json

# 今週の目標を確認
bin/pdca goal current --json

# 既存の目標を上書きして再作成（⚠️ 実行前に現在の目標を確認し、ユーザーに上書き確認を取ること）
bin/pdca goal create --items "新目標" --force --json

# 目標一覧
bin/pdca goal list --json
```

### PDCA報告
```bash
# 報告作成
bin/pdca report create --status green --plan "学習内容" --do "実施内容" --check "振り返り" --action "次のアクション" --json

# 今日の報告取得
bin/pdca report today --json

# 報告更新
bin/pdca report update --date YYYY-MM-DD --do "..." --check "..." --action "..." --json

# 報告一覧
bin/pdca report list --month YYYY-MM --json
```

### 講師向け: 受講生管理
```bash
# 受講生一覧
bin/pdca student list --json
bin/pdca student list --status active --json
bin/pdca student list --team "Aチーム" --json

# 受講生詳細
bin/pdca student show --id 1 --json
```

### 講師向け: 進捗確認
```bash
# 全受講生の進捗一覧
bin/pdca progress list --json
bin/pdca progress list --team "Aチーム" --json

# 受講生個別の進捗詳細
bin/pdca progress show --id 1 --json
```

### 講師向け: ダッシュボード
```bash
# 日別報告状況（デフォルト: 昨日）
bin/pdca dashboard daily --json
bin/pdca dashboard daily --date 2026-04-11 --json
bin/pdca dashboard daily --status not_submitted --json
bin/pdca dashboard daily --team "Aチーム" --json

# 週別報告状況（デフォルト: 今週）
bin/pdca dashboard weekly --json
bin/pdca dashboard weekly --week_offset -1 --json
bin/pdca dashboard weekly --team "Aチーム" --json
```

### コメント（講師・受講生共通）
```bash
# コメント一覧（report_idはreport list等で取得）
bin/pdca comment list --report_id 1 --json

# コメント投稿
bin/pdca comment create --report_id 1 --content "コメント内容" --json

# コメント削除（投稿者本人のみ）
bin/pdca comment delete --id 1 --json
```

### 学習時間（S5）
```bash
# 実績の記録
bin/pdca study log --date 2026-04-17 --slots "09:00-12:00" "14:00-17:00" --json

# 学習時間を表示（予定・実績両方）
bin/pdca study show --date 2026-04-17 --json
```

### 週次目標進捗%（E8）
```bash
# 単体更新（現在の週の目標が自動選択される）
bin/pdca goal progress --item_id 5 --progress 50 --json

# 一括更新
bin/pdca goal progress --progresses "5:50" "6:80" --json
```

### 日次目標（S3 + E6）
```bash
# 指定日の日次目標を表示
bin/pdca daily show --date 2026-04-17 --json

# 週単位で一覧
bin/pdca daily list --week 2026-04-13 --json

# アイテムの Plan 内容を更新（id=内容 形式、最初の = で分割）
bin/pdca daily update --date 2026-04-17 --plans "101=Ruby配列" "102=hash演習" --json
```

### コード提出（E9）
```bash
# 作成時にコード添付
bin/pdca report create --status green --plan "..." --curriculum "Ruby基礎" --code "def hello; end" --json

# ファイルから読み込み
bin/pdca report create --plan "..." --curriculum "Ruby基礎" --code_file ./solution.rb --json

# 更新時も同様
bin/pdca report update --date 2026-04-17 --code "新しいコード" --json
```

## learning_status の値
- `green`: 順調、問題なし
- `yellow`: 少し詰まっているが対処できそう
- `red`: 完全に止まっている

## 注意事項
- `--json` フラグで機械可読なJSON出力を得る（AI連携時は常に使用推奨）
- report_date は YYYY-MM-DD 形式（省略時は今日）
- 1日1報告の制約あり（同じ日付で再度createするとエラー、updateで更新）
- 未来日はPlanのみ入力可能（Do/Check/Actionは無視される）
- `--category_ids` は `plan show --json` で取得できるカテゴリIDを指定
- `--force` による目標上書きは既存目標を削除するため、必ずユーザーに確認を取る
- `--team` はチーム名の完全一致でフィルタ（部分一致不可）。チーム名は `student list --json` で確認可能
- `--code` と `--code_file` は排他。両方指定するとエラー
- `daily update --plans` は `id=内容` 形式。最初の `=` で分割するため、内容に `=` や `:` を含められる
- `study log` は実績(actual)のみ対応。予定(planned)はWeb側から入力
- `goal progress` は `--item_id + --progress`（単体）か `--progresses "id:%"`（一括）のどちらか一方を指定

## サーバー停止時のフォールバック

サーバー (Heroku) が 5xx を返したり接続不能な状態でも、`/pdca-report` スキル経由ならローカルに一時保存される:

- 保存先: `~/.pdca/queue/`
- 形式: `{user_id}__report_create__{YYYY-MM-DD}.json`
- 復旧後、次回 `/pdca-report` 実行時に自動同期（本番に同日報告がなければ投稿）
- 競合（本番側に既に同日報告あり）は `~/.pdca/queue/conflicts/` に退避
- 人間用バックアップは `docs/reports/{date}.md` に常時保存（queue とは独立）

## 終了コード
- 0: 成功
- 1: 認証エラー / ネットワークエラー
- 2: バリデーションエラー

## 設定
- 設定ファイル: `~/.pdca.yml`（api_url, token）
- 環境変数: `PDCA_API_URL`, `PDCA_TOKEN` で上書き可能
- 初回は `bin/pdca login` でセットアップが必要
