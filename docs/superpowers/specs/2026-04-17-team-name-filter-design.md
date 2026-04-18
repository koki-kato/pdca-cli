# 講師向けコマンドのチームフィルタを名前指定に変更

- **Issue**: [#29](https://github.com/koki-kato/pdca-app/issues/29)
- **作成日**: 2026-04-17
- **ステータス**: 設計完了（実装前）
- **対象リポジトリ**:
  - CLI: `pdca-cli`（このリポジトリ）
  - API: `occ_pdca_app`（別リポジトリ、連動PR必須）

## 目的

講師向けコマンドのチームフィルタを、覚えにくいID指定（`--team_id 5`）から直感的な名前指定（`--team "Aチーム"`）に変更する。CLI直接実行時のUXを向上させる。

## 背景

Issue #14 (I1) および Issue #20 (I7) では当初 `--team "チーム名"` として設計されていたが、API側が `team_id` のみ対応だったため、暫定的に `--team_id` として実装された。本改修でAPIに `team_name` パラメータを追加し、CLIを当初の設計に揃える。

Claude Code経由で使う場合は `student list --json` からチーム名を取得して完全一致で投げる運用が自然なため、名前検索の方が親和性が高い。

## スコープ

### 対象コマンド（4つ）

Issue #29 本文では `student list` と `progress list` のみが対象だが、CLIのUX一貫性を重視し、`--team_id` を使用している全コマンドを一括変更する。

- `pdca student list`
- `pdca progress list`
- `pdca dashboard daily`
- `pdca dashboard weekly`

### 対象外

- 上記以外のコマンド（`--team_id` を使っていない）

## 設計方針

### 1. CLIオプションの変更

`--team_id`（数値） → `--team`（文字列）に**完全置換**。後方互換は持たない。

- 理由: CLIはまだ新しく、利用者が限定的。2つのオプションが混在すると将来的な技術的負債になる。

### 2. APIパラメータの変更

`team_name` パラメータを**追加**し、既存の `team_id` は**当面残す**（後方互換）。

- 理由: Web側（`StudentsController` 等）が内部で `team_id` を使用している可能性があり、Web機能を壊さないため。
- `team_id` と `team_name` が両方指定された場合: 両方の条件で AND 絞り込み（自然な挙動）。

### 3. 検索方式

**完全一致**（`WHERE teams.name = ?`）。

- 理由: 講師はチーム名を正確に把握している前提でよい（`student list --json` 等で確認可能）。部分一致は「Aチーム」と「AAチーム」の混同リスクがある。将来的に部分一致が必要になれば別オプション（`--team-contains` 等）で追加可能。

### 4. エッジケース

- **存在しないチーム名**: 空配列を返す（エラーにしない）
  - 理由: 「フィルタ結果が0件」と「該当チームが存在しない」はユーザー視点では同じ。
- **同名チームが複数存在**: 該当する全チームの受講生を返す（DB上 unique 制約が無い場合）
  - 要確認: API側で `teams.name` に unique 制約があるか。ある場合はこの考慮は不要。
- **空文字列 `--team ""`**: フィルタ無しとして扱う（Ruby的に `""` はtruthyなので `if team && !team.empty?` でガード）

## 実装内容

### CLI側（pdca-cli）

#### `lib/pdca_cli/cli.rb`（4箇所）

オプション定義とメソッド呼び出しを変更。

```ruby
# Before
option :team_id, type: :numeric, desc: "チームIDでフィルタ"
client.list_students(status: options[:status], team_id: options[:team_id])

# After
option :team, type: :string, desc: "チーム名でフィルタ（完全一致）"
client.list_students(status: options[:status], team: options[:team])
```

#### `lib/pdca_cli/client.rb`（4メソッド）

メソッドシグネチャとクエリパラメータを変更。APIには `team_name` として送る。

```ruby
# Before
def list_students(status: nil, team_id: nil)
  query = {}
  query[:status] = status if status
  query[:team_id] = team_id if team_id
  get("/api/v1/instructor/students", query)
end

# After
def list_students(status: nil, team: nil)
  query = {}
  query[:status] = status if status
  query[:team_name] = team if team && !team.empty?
  get("/api/v1/instructor/students", query)
end
```

対象メソッド:
- `list_students`
- `list_progress`
- `dashboard_daily`
- `dashboard_weekly`

#### `CLAUDE.md` の更新

`--team_id N` の記載を `--team "チーム名"` に更新（4コマンド分）。

### API側（occ_pdca_app）

CLI側のPRと連動させる。PR説明に CLI 側 PR へのリンクを記載。

#### 変更対象コントローラ

- `app/controllers/api/v1/instructor/students_controller.rb`
- `app/controllers/api/v1/instructor/progress_controller.rb`
- `app/controllers/api/v1/instructor/dashboard_controller.rb`（daily/weekly両方）

#### 変更内容

各コントローラで `team_name` パラメータを受け付け、チーム名で join して絞り込む。`team_id` は既存のまま残す。

```ruby
# 例: students_controller.rb
scope = User.where(role: :student)
scope = scope.where(team_id: params[:team_id]) if params[:team_id].present?
scope = scope.joins(:team).where(teams: { name: params[:team_name] }) if params[:team_name].present?
```

ルーティング・マイグレーションは不要（パラメータ追加のみ）。

## テスト方針

### CLI側（RSpec）

- `spec/pdca_cli/cli_spec.rb`: 各コマンドで `--team "チーム名"` が API に `team_name=XXX` として送信されることを確認
- `spec/pdca_cli/client_spec.rb`: クライアントメソッドが正しいクエリパラメータを生成することを確認
- 既存の `--team_id` テストは削除（完全置換のため）

### API側（RSpec）

- 各コントローラの request spec に `team_name` パラメータのテストを追加
- カバーするケース:
  - 完全一致でフィルタできる
  - 存在しないチーム名で空配列を返す
  - `team_id` との AND 絞り込みが機能する

## リリース順序（重要）

順序を守らないと、新CLIが旧APIを叩いて `team_name` が無視され、フィルタが効かずに全件返る不具合が起きる。

1. **API側を先にデプロイ**（`team_name` パラメータを受け付けられる状態に）
2. **CLI側をリリース**（`--team` を使い始める）

## PR構成

- **CLI側PR**: このリポジトリに作成
- **API側PR**: `occ_pdca_app` に作成し、CLI側PRへのリンクを記載
- 両PR の説明文に相互リンクを貼り、レビュー時に連動していることを明示

## 未決事項

- API側 `teams` テーブルの `name` カラムに unique 制約があるか要確認（実装時に調査）
  - 制約あり: 「同名チーム複数」のエッジケース考慮不要
  - 制約なし: 設計方針4の通り、全チームの受講生を合わせて返す
