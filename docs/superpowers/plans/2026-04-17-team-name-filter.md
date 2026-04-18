# チームフィルタ名前指定化 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 講師向けコマンド（student/progress/dashboard）のチームフィルタを `--team_id N` から `--team "チーム名"` に完全置換する。

**Architecture:** CLI側は `--team_id` を `--team` に置換し、API呼び出し時は `team_name` クエリパラメータに変換して送信する。API側（`occ_pdca_app`）は別PRで `team_name` パラメータ受付を追加（本プランの対象外）。

**Tech Stack:** Ruby 3.0+, Thor 1.3, Faraday（既存のHTTPクライアント）

**対応Issue:** [#29](https://github.com/koki-kato/pdca-app/issues/29)

**関連スペック:** [docs/superpowers/specs/2026-04-17-team-name-filter-design.md](../specs/2026-04-17-team-name-filter-design.md)

---

## 前提・リリース順序（重要）

**API側 PR のマージ・本番デプロイが先**、CLI側 PR のマージが後。

順序を間違えると、新CLI（`team_name` を送信）が旧API（`team_name` を受け付けない）を叩いてフィルタが効かず全件返る不具合になる。

API側の変更内容:
- `app/controllers/api/v1/instructor/students_controller.rb`
- `app/controllers/api/v1/instructor/progress_controller.rb`
- `app/controllers/api/v1/instructor/dashboard_controller.rb`
- 各コントローラで `params[:team_name]` を joins(:team).where(teams: { name: ... }) で絞り込み
- `params[:team_id]` は既存のまま残す（後方互換）

---

## ファイル構造

### 変更ファイル

| ファイル | 変更内容 | 責務 |
|---------|---------|------|
| `lib/pdca_cli/client.rb` | 4メソッドのパラメータ名 `team_id` → `team` に変更、APIクエリは `team_name` に変換 | APIクライアント層 |
| `lib/pdca_cli/cli.rb` | 4コマンドのThorオプション `--team_id` → `--team`、クライアント呼び出し調整 | CLIインターフェース層 |
| `CLAUDE.md` | 講師向けコマンドの使用例を `--team_id N` から `--team "チーム名"` に更新 | ドキュメント |

### テストについて

既存プロジェクトにRSpec等のテストディレクトリ・依存関係が存在しないため、CLI側はテストコードは書かず**手動動作確認**で検証する（既存の実装パターンに従う：#14, #15, #20 など過去のfeatコミットもテストなし）。

API側は `occ_pdca_app` の既存テスト規約（RSpec request spec）に従って別PR内で追加する。

---

## Task 1: client.rb の4メソッドを `team_id` → `team` に変更

**Files:**
- Modify: `lib/pdca_cli/client.rb:98-134`

- [ ] **Step 1: `list_students` の変更**

`lib/pdca_cli/client.rb:98-103` を以下に変更:

```ruby
# 講師向け: 受講生
def list_students(status: nil, team: nil)
  query = {}
  query[:status] = status if status
  query[:team_name] = team if team && !team.empty?
  get("/api/v1/instructor/students", query)
end
```

- [ ] **Step 2: `list_progress` の変更**

`lib/pdca_cli/client.rb:110-114` を以下に変更:

```ruby
# 講師向け: 進捗確認
def list_progress(team: nil)
  query = {}
  query[:team_name] = team if team && !team.empty?
  get("/api/v1/instructor/progress", query)
end
```

- [ ] **Step 3: `dashboard_daily` の変更**

`lib/pdca_cli/client.rb:121-127` を以下に変更:

```ruby
def dashboard_daily(date: nil, team: nil, status: nil)
  query = {}
  query[:date] = date if date
  query[:team_name] = team if team && !team.empty?
  query[:status] = status if status
  get("/api/v1/instructor/dashboard/daily", query)
end
```

- [ ] **Step 4: `dashboard_weekly` の変更**

`lib/pdca_cli/client.rb:129-134` を以下に変更:

```ruby
def dashboard_weekly(week_offset: nil, team: nil)
  query = {}
  query[:week_offset] = week_offset if week_offset
  query[:team_name] = team if team && !team.empty?
  get("/api/v1/instructor/dashboard/weekly", query)
end
```

- [ ] **Step 5: Ruby構文チェック**

```bash
ruby -c lib/pdca_cli/client.rb
```

Expected: `Syntax OK`

- [ ] **Step 6: コミット**

```bash
git add lib/pdca_cli/client.rb
git commit -m "refactor: client.rb のチームフィルタを team_id → team に変更 (#29)"
```

---

## Task 2: cli.rb の4コマンドのオプションを `--team_id` → `--team` に変更

**Files:**
- Modify: `lib/pdca_cli/cli.rb:669, 674`（student list）
- Modify: `lib/pdca_cli/cli.rb:747, 752`（progress list）
- Modify: `lib/pdca_cli/cli.rb:827, 835`（dashboard daily）
- Modify: `lib/pdca_cli/cli.rb:877, 884`（dashboard weekly）

- [ ] **Step 1: `student list` のオプション変更**

`lib/pdca_cli/cli.rb:669` を:
```ruby
option :team_id, type: :numeric, desc: "チームIDでフィルタ"
```
に以下に変更:
```ruby
option :team, type: :string, desc: "チーム名でフィルタ（完全一致）"
```

`lib/pdca_cli/cli.rb:674` を:
```ruby
result = client.list_students(status: options[:status], team_id: options[:team_id])
```
に以下に変更:
```ruby
result = client.list_students(status: options[:status], team: options[:team])
```

- [ ] **Step 2: `progress list` のオプション変更**

`lib/pdca_cli/cli.rb:747` を:
```ruby
option :team_id, type: :numeric, desc: "チームIDでフィルタ"
```
に以下に変更:
```ruby
option :team, type: :string, desc: "チーム名でフィルタ（完全一致）"
```

`lib/pdca_cli/cli.rb:752` を:
```ruby
result = client.list_progress(team_id: options[:team_id])
```
に以下に変更:
```ruby
result = client.list_progress(team: options[:team])
```

- [ ] **Step 3: `dashboard daily` のオプション変更**

`lib/pdca_cli/cli.rb:827` を:
```ruby
option :team_id, type: :numeric, desc: "チームIDでフィルタ"
```
に以下に変更:
```ruby
option :team, type: :string, desc: "チーム名でフィルタ（完全一致）"
```

`lib/pdca_cli/cli.rb:833-837` の `client.dashboard_daily(...)` 呼び出しを以下に変更:
```ruby
result = client.dashboard_daily(
  date: options[:date],
  team: options[:team],
  status: options[:status]
)
```

- [ ] **Step 4: `dashboard weekly` のオプション変更**

`lib/pdca_cli/cli.rb:877` を:
```ruby
option :team_id, type: :numeric, desc: "チームIDでフィルタ"
```
に以下に変更:
```ruby
option :team, type: :string, desc: "チーム名でフィルタ（完全一致）"
```

`lib/pdca_cli/cli.rb:882-885` の `client.dashboard_weekly(...)` 呼び出しを以下に変更:
```ruby
result = client.dashboard_weekly(
  week_offset: options[:week_offset],
  team: options[:team]
)
```

- [ ] **Step 5: Ruby構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 6: 旧オプション `--team_id` が残っていないことを確認**

```bash
grep -n "team_id" lib/pdca_cli/cli.rb
```

Expected: 何も出力されない（0件）

- [ ] **Step 7: コミット**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: 講師向けコマンドの --team_id を --team（チーム名）に変更 (#29)"
```

---

## Task 3: CLAUDE.md の使用例を更新

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: CLAUDE.md 内の `--team_id` 記載を確認**

```bash
grep -n "team_id" CLAUDE.md
```

各行の前後を確認し、以下の置換対象を特定する（`--category_ids` は別機能なので対象外）。

- [ ] **Step 2: `student list` のセクションを更新**

`bin/pdca student list --json`、`bin/pdca student list --status active --json` の記載は維持したまま、チーム関連の使用例を以下のように追加（既存にチーム例が無ければ追加、あれば差し替え）:

```bash
bin/pdca student list --team "Aチーム" --json
```

- [ ] **Step 3: `progress list` のセクションを更新**

同様に:

```bash
bin/pdca progress list --team "Aチーム" --json
```

- [ ] **Step 4: `dashboard daily` / `dashboard weekly` のセクションを更新**

もしチーム例が記載されていれば、`--team_id N` を `--team "チーム名"` に置換。記載が無ければ追記不要。

- [ ] **Step 5: 最終確認**

```bash
grep -n "team_id" CLAUDE.md
```

Expected: `--category_ids` 以外に `team_id` が残っていない

- [ ] **Step 6: コミット**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md のチームフィルタ例を --team（名前指定）に更新 (#29)"
```

---

## Task 4: 手動動作確認

**前提:** API側のPRがマージされ、本番環境（Heroku）に `team_name` パラメータ対応がデプロイ済みであること。未デプロイの場合は、ローカルAPI環境（`PDCA_API_URL` 環境変数で切り替え）で確認する。

- [ ] **Step 1: ヘルプ表示で新オプションが反映されているか確認**

```bash
bin/pdca student list --help
```

Expected: `--team=TEAM` が表示され、`--team_id` は表示されない。

同様に:
```bash
bin/pdca progress list --help
bin/pdca dashboard daily --help
bin/pdca dashboard weekly --help
```

- [ ] **Step 2: `student list --team` の動作確認**

```bash
bin/pdca student list --json
```

JSON出力から任意のチーム名を取得し（`students[*].teams[0]`）、そのチーム名で絞り込み:

```bash
bin/pdca student list --team "取得したチーム名" --json
```

Expected: 指定チームに所属する受講生のみが返る。

- [ ] **Step 3: 存在しないチーム名で空配列が返ることを確認**

```bash
bin/pdca student list --team "__not_existing_team_xyz__" --json
```

Expected: `{"students":[],"total":0,...}` のように空配列で正常終了（exit code 0）。

- [ ] **Step 4: `progress list --team` の動作確認**

```bash
bin/pdca progress list --team "取得したチーム名" --json
```

Expected: 指定チームの進捗のみが返る。

- [ ] **Step 5: `dashboard daily --team` の動作確認**

```bash
bin/pdca dashboard daily --team "取得したチーム名" --json
```

Expected: 指定チームの日別報告状況のみが返る。

- [ ] **Step 6: `dashboard weekly --team` の動作確認**

```bash
bin/pdca dashboard weekly --team "取得したチーム名" --json
```

Expected: 指定チームの週別報告状況のみが返る。

- [ ] **Step 7: 動作確認結果のメモ**

コマンド実行結果をPRの説明文に貼り付けできるようメモしておく。問題があればTask 1-3に戻って修正。

---

## Task 5: PR作成

**Files:**
- なし（GitHub操作のみ）

- [ ] **Step 1: ブランチをリモートにpush**

```bash
git push -u origin feature/i29-team-name-filter
```

- [ ] **Step 2: CLI側PRを作成**

```bash
gh pr create --title "feat: 講師向けコマンドのチームフィルタを --team（名前指定）に変更 (#29)" --body "$(cat <<'EOF'
## 概要

[Issue #29](https://github.com/koki-kato/pdca-app/issues/29) 対応。講師向けコマンドのチームフィルタを `--team_id N` から `--team "チーム名"` に完全置換。

## 変更内容

- `lib/pdca_cli/client.rb`: 4メソッドの `team_id:` 引数を `team:` に変更、APIへは `team_name` パラメータとして送信
- `lib/pdca_cli/cli.rb`: 4コマンド（student list / progress list / dashboard daily / dashboard weekly）の `--team_id` オプションを `--team` に置換
- `CLAUDE.md`: 使用例を更新
- `docs/superpowers/specs/2026-04-17-team-name-filter-design.md`: 設計ドキュメント
- `docs/superpowers/plans/2026-04-17-team-name-filter.md`: 実装計画

## 前提

**API側 PR（別リポジトリ `occ_pdca_app`）** のマージ・本番デプロイが先。API側でCLI側PR（本PR）へのリンクを貼っているはずなので相互参照してください。

## テスト方針

既存プロジェクトにテストディレクトリが無いため、手動動作確認で検証（過去の講師向け機能追加 #14/#15/#20 と同じ方針）。

## Test plan

- [ ] `bin/pdca student list --help` で `--team` オプションが表示される
- [ ] `bin/pdca student list --team "チーム名" --json` でフィルタが機能する
- [ ] `bin/pdca progress list --team "チーム名" --json` でフィルタが機能する
- [ ] `bin/pdca dashboard daily --team "チーム名" --json` でフィルタが機能する
- [ ] `bin/pdca dashboard weekly --team "チーム名" --json` でフィルタが機能する
- [ ] 存在しないチーム名指定で空配列が返る

## 関連

- API側PR: （API側PR作成後にリンク追記）
EOF
)"
```

- [ ] **Step 3: API側PRへのリンクを追記（API側PR作成後）**

API側PRを作成したら、本PRの説明文の「関連」セクションにAPI側PRのURLを追記する:

```bash
gh pr edit --body "$(gh pr view --json body -q .body | sed 's|（API側PR作成後にリンク追記）|https://github.com/koki-kato/occ_pdca_app/pull/XXX|')"
```

または手動でGitHub UIから編集。

---

## 完了基準

- [ ] Task 1-5 の全ステップが完了
- [ ] API側PRがマージ・デプロイされている
- [ ] CLI側PRがレビュー通過
- [ ] 手動動作確認で4コマンド全てフィルタが機能する
- [ ] Issue #29 がClose可能な状態
