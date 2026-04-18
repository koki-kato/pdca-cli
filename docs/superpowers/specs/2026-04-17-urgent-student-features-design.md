# 受講生向け急ぎ機能バンドル 設計ドキュメント

- **作成日**: 2026-04-17
- **対応Issue**: #12 (S5) / #32 (E8) / #33 (E9) / #21 (E6) + #10 (S3)
- **ブランチ**: `feature/urgent-student-features`（CLI・API 共通）
- **優先度**: 高（本家学習媒体のドリル対応要件に連動）

## 目的

本家学習媒体との連携・ドリル対応要件に対応するため、受講生向けCLI機能を4つまとめて追加する。急ぎ対応のため、1つのPRに4機能をバンドルし、各機能はミニマムスコープで実装する。

## 対象機能と優先スコープ

「欲張らない」方針。各Issue本文に記載された構想のうち、必須のユースケースに絞る。

| # | 機能 | 対応Issue | API変更 | CLI変更 |
|---|------|---------|---------|--------|
| ① | 学習時間入力（実績のみ） | #12 (S5) | 新規Controller追加 | 新規 `study` サブコマンド |
| ② | 週次進捗%変更 | #32 (E8) | 既存 `weekly_goals#update` 拡張 | 既存 `goal progress` サブコマンド追加 |
| ③ | コード提出（カリキュラム名・code_content） | #33 (E9) | `report_json` に1フィールド追加 | 既存 `report create/update` にオプション追加 |
| ④ | 日次目標管理（show/list/update） | #21 (E6) + #10 (S3) 統合 | 新規Controller追加 | 新規 `daily` サブコマンド |

---

## ① 学習時間入力 (S5)

### スコープ
- **実績(actual)の記録のみ対応**。予定(planned)およびテンプレート連携（#9 S2 範囲）は後回し
- 対象テーブル: `study_times`（報告紐づき）+ `study_time_slots`（`slot_type` で planned/actual 区別）

### 仕様

**CLI**
```bash
# 実績記録（既存報告に紐づけ）
pdca study log --date 2026-04-17 --slots "09:00-12:00" "14:00-17:00" --json

# 表示（予定・実績両方を返す）
pdca study show --date 2026-04-17 --json
```

**APIエンドポイント**
- `POST /api/v1/study_times` — 指定日の report に紐づく学習時間スロットを（実績のみ）記録
  - Request: `{ date: "YYYY-MM-DD", slot_type: "actual", slots: ["09:00-12:00", ...] }`
- `GET /api/v1/study_times?date=YYYY-MM-DD` — 指定日の学習時間情報（planned/actual両方）

### 設計判断
- 対応する `pdca_report` が存在しない日には **422エラー**（先に `report create` が必要）
- 時間帯フォーマット: `"HH:MM-HH:MM"`（24時間表記、半角コロン）
- 既存の actual スロットは **全削除 → 新規作成**（差分管理せず）

---

## ② 週次進捗%変更 (E8)

### スコープ
- 既存の `weekly_goal_items.progress` カラム（integer 0-100）への更新対応
- 単体・一括両方をサポート
- バリデーション: 0-100 の整数のみ許可

### 仕様

**CLI**
```bash
# 単体更新
pdca goal progress --item_id 5 --progress 50 --json

# 一括更新
pdca goal progress --progresses "5:50" "6:80" "7:100" --json
```

**API**
- 既存 `PATCH /api/v1/weekly_goals/:id` の `update` アクションに `items` attribute を追加
- strong params 拡張: `items_attributes: [:id, :progress]`
  - content（E1 で対応済み）と progress が同時更新可能

### 設計判断
- 単体指定と一括指定は排他（両方指定されたらエラー）
- 0-100 以外の値はバリデーションエラー（API側で弾く）
- item_id が週次目標に属さない場合 403/404 エラー

---

## ③ コード提出 (E9)

### スコープ
- `pdca_reports.curriculum_name` / `code_content` カラム（既存）の読み書き
- 対象コマンド: `report create`, `report update`, `report show`, `report today`, `report list`

### 仕様

**CLI**
```bash
# 作成時
pdca report create --status green --plan "..." --curriculum "Ruby基礎" --code "def hello; end" --json

# コードをファイルから読み込み
pdca report create --plan "..." --curriculum "Ruby基礎" --code_file ./solution.rb --json

# 更新時
pdca report update --date 2026-04-17 --curriculum "..." --code "..." --json

# 表示時（既存コマンド。JSON出力に code_content が含まれる）
pdca report show --date 2026-04-17 --json
pdca report today --json
```

### API変更
- `app/controllers/api/v1/reports_controller.rb#report_json` に `code_content: report.code_content` を1行追加
- strong params は既存（L112）で対応済みのため追加不要

### 設計判断
- `--code` と `--code_file` は排他（両方指定されたらエラー）
- 人間向け出力では code_content が長い場合は先頭N文字で省略
- 既存の `--curriculum` オプション（cli.rb:79）は既に存在するため利用（`--curriculum_name` ではなく `--curriculum`）

---

## ④ 日次目標管理 (E6 + S3 統合)

### スコープ
- 週次目標作成時に自動生成される daily_goal_items の読み書き
- `content`（= Plan）の更新をサポート
- 対象テーブル: `daily_goals`（日単位） + `daily_goal_items`（アイテム単位）

### 仕様

**CLI**
```bash
# 指定日の日次目標アイテム表示
pdca daily show --date 2026-04-17 --json

# 週単位で一覧
pdca daily list --week 2026-04-13 --json

# アイテムの content 更新（複数可、ID=内容 形式。最初の=で分割）
pdca daily update --date 2026-04-17 --plans "101=Ruby配列" "102=Ruby hash: Array操作と対比" --json
```

**API**
- 新規Controller: `app/controllers/api/v1/daily_goals_controller.rb`
  - `GET /api/v1/daily_goals?date=YYYY-MM-DD` — 指定日の daily_goal と items を返す
  - `GET /api/v1/daily_goals?week=YYYY-MM-DD` — 週単位一覧（週頭日を指定）
  - `PATCH /api/v1/daily_goals/:daily_goal_id/items/:id` — アイテム content 更新
- ルート追加: `resources :daily_goals, only: [:index] do resources :items, only: [:update], controller: "daily_goal_items" end` など

### 設計判断
- `pdca daily update --plans "id=内容"` の区切り文字は **最初の`=`** で分割（内容にコロンや`=`を含めても後半は無視される）
- ID指定は必須（date 経由の自動解決はしない — 明示的に item_id を渡す運用）
- 空配列で既存の daily_goal 未存在日（週次目標作成前）は空を返す
- current_user スコープで本人のデータのみアクセス可能（401/403 保護）

---

## 認可・セキュリティ

- すべてのエンドポイントは `Api::V1::BaseController`（既存）を継承し、`current_user` スコープで本人リソースのみアクセス可能
- 他ユーザーの study_times / weekly_goals / reports / daily_goals にはアクセスできない

## テスト方針

- **CLI側**: 既存プロジェクト方針通りテスト無し（手動動作確認）
- **API側**: Minitest で各エンドポイント + 認可テスト + バリデーションテストを追加

## リリース順序

API側PRを先にマージ・デプロイ → CLI側PRをマージ（#29と同じ運用）。
ただし今回は同一ブランチ名 `feature/urgent-student-features` で両リポジトリを並行作業するため、**最終的にCLI PRとAPI PRの2つ**が提出される。

## スコープ外（本PRでやらないこと）

以下は別Issueで残るため、本PRでは対応しない：

- **学習時間の予定(planned)記録**: S5 の全要件。本PR は actual のみ
- **学習時間テンプレート管理**: #9 S2
- **カリキュラム進捗完了チェック**: #11 S4
- **週次目標の削除**: #7 E5
- **PDCA報告の削除**: #6 E4

## PR構成

- CLI側: `koki-kato/pdca-cli` に PR 作成
- API側: `koki-kato/pdca-app` に PR 作成
- 両PR の説明文に4つのIssue番号（#12, #32, #33, #21, #10）をリンク、相互リンクも記載
