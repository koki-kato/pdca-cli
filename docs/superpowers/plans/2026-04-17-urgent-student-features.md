# 受講生向け急ぎ機能バンドル 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本家学習媒体のドリル対応要件に応えるため、4つの受講生向けCLI機能（学習時間/進捗%/コード提出/日次目標管理）を1PRにまとめて実装する。

**Architecture:** API側は最小追加（新規コントローラー2本 + 既存レスポンス1行追加）、CLI側は新規サブコマンド3本 + 既存 `report` コマンドの拡張。4機能はそれぞれ独立しており、同一ブランチで並行実装可能。

**Tech Stack:** CLI: Ruby 3.0+ / Thor 1.3、API: Rails 7.1 / Minitest / SQLite (dev) + MySQL (prod)

**関連Issue:** #12 (S5) / #32 (E8) / #33 (E9) / #21 (E6) / #10 (S3)

**関連スペック:** [docs/superpowers/specs/2026-04-17-urgent-student-features-design.md](../specs/2026-04-17-urgent-student-features-design.md)

---

## 重要な前提・発見事項

### E8 は API変更不要
`weekly_goals_controller#update` の L100-109 で既に `progress` attr の permit 済み。CLI側だけで対応可能。

### 作業ディレクトリ
- **CLI側**: `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features` （ブランチ `feature/urgent-student-features`）
- **API側**: `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features` （ブランチ `feature/urgent-student-features`）

### リリース順
API側PR → マージ・デプロイ → CLI側PR。

---

## ファイル構造

### API側（`occ_pdca_app`）

| ファイル | 変更種別 | 責務 |
|---------|---------|------|
| `app/controllers/api/v1/reports_controller.rb` | 修正1行 | `report_json` に `code_content` 追加 |
| `app/controllers/api/v1/study_times_controller.rb` | 新規 | 学習時間記録・表示（実績のみ） |
| `app/controllers/api/v1/daily_goals_controller.rb` | 新規 | 日次目標の show/list/update |
| `config/routes.rb` | 修正 | 上記2コントローラーのルート追加 |
| `test/controllers/api/v1/study_times_controller_test.rb` | 新規 | S5のAPIテスト |
| `test/controllers/api/v1/daily_goals_controller_test.rb` | 新規 | E6+S3のAPIテスト |

### CLI側（`pdca-cli`）

| ファイル | 変更種別 | 責務 |
|---------|---------|------|
| `lib/pdca_cli/client.rb` | 修正 | 新規APIメソッド追加（study/daily/goal_progress） |
| `lib/pdca_cli/cli.rb` | 修正 | 新規サブコマンド追加 + `report` 拡張 |
| `CLAUDE.md` | 修正 | 全機能の使用例と注意事項追加 |

CLI側にテストは書かない（既存プロジェクト方針）。

---

## Task 1: API - reports_controller.rb の report_json に code_content 追加（E9）

**Files:**
- Modify: `app/controllers/api/v1/reports_controller.rb:116-128`

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: `report_json` に code_content を追加**

`app/controllers/api/v1/reports_controller.rb` の `report_json` メソッドの `curriculum_name: report.curriculum_name,` 直後に `code_content: report.code_content,` を追加する：

```ruby
def report_json(report)
  {
    id: report.id,
    report_date: report.report_date&.iso8601,
    learning_status: report.learning_status,
    learning_plan: report.learning_plan,
    learning_do: report.learning_do,
    learning_check: report.learning_check,
    learning_action: report.learning_action,
    curriculum_name: report.curriculum_name,
    code_content: report.code_content,
    created_at: report.created_at&.iso8601,
    updated_at: report.updated_at&.iso8601
  }
end
```

- [ ] **Step 2: Ruby構文チェック**

```bash
ruby -c app/controllers/api/v1/reports_controller.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: 既存テスト実行**

```bash
bin/rails test test/controllers/api/v1/reports_controller_test.rb 2>&1 | tail -5
```

Expected: 0 failures, 0 errors

- [ ] **Step 4: Commit**

```bash
git add app/controllers/api/v1/reports_controller.rb
git commit -m "feat: report_json に code_content を追加 (#33)"
```

---

## Task 2: API - study_times_controller.rb 新規作成（S5）

**Files:**
- Create: `app/controllers/api/v1/study_times_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/study_times_controller_test.rb`

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: ルート追加**

`config/routes.rb` の `namespace :api do namespace :v1 do` 内に、`resources :reports` の近くに以下を追加（api v1 スコープ内）：

```ruby
resources :study_times, only: [:index, :create]
```

追加先の位置は既存 `resources :reports` の直後。

- [ ] **Step 2: Controller新規作成**

`app/controllers/api/v1/study_times_controller.rb` を作成：

```ruby
module Api
  module V1
    class StudyTimesController < BaseController
      before_action :require_student!

      # GET /api/v1/study_times?date=YYYY-MM-DD
      def index
        date = parse_date(params[:date])
        unless date
          render json: { error: 'date パラメータが必要です（例: 2026-04-17）' }, status: :bad_request
          return
        end

        report = current_user.pdca_reports.find_by(report_date: date)
        unless report
          render json: { error: '指定日の報告が見つかりません' }, status: :not_found
          return
        end

        study_time = report.study_time
        render json: {
          date: date.iso8601,
          planned_slots: study_time ? slots_json(study_time.planned_slots) : [],
          actual_slots:  study_time ? slots_json(study_time.actual_slots)  : []
        }
      end

      # POST /api/v1/study_times
      # Body: { date: "YYYY-MM-DD", slot_type: "actual", slots: ["09:00-12:00", ...] }
      def create
        date = parse_date(params[:date])
        unless date
          render json: { error: 'date パラメータが必要です（例: 2026-04-17）' }, status: :bad_request
          return
        end

        slot_type = params[:slot_type] || 'actual'
        unless %w[actual planned].include?(slot_type)
          render json: { error: 'slot_type は actual または planned を指定してください' }, status: :bad_request
          return
        end

        report = current_user.pdca_reports.find_by(report_date: date)
        unless report
          render json: { error: '指定日の報告が見つかりません（先に report create が必要）' }, status: :unprocessable_entity
          return
        end

        parsed_slots = parse_slots(params[:slots])
        if parsed_slots.nil?
          render json: { error: 'slots の形式が不正です（例: "09:00-12:00"）' }, status: :bad_request
          return
        end

        study_time = report.study_time || report.build_study_time
        ActiveRecord::Base.transaction do
          study_time.save! if study_time.new_record?
          # 指定 slot_type の既存スロットを全削除してから新規作成
          study_time.study_time_slots.where(slot_type: slot_type).destroy_all
          parsed_slots.each do |(start_t, end_t)|
            study_time.study_time_slots.create!(start_time: start_t, end_time: end_t, slot_type: slot_type)
          end
        end

        render json: {
          date: date.iso8601,
          planned_slots: slots_json(study_time.reload.planned_slots),
          actual_slots:  slots_json(study_time.actual_slots)
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "学習時間の保存に失敗しました: #{e.message}" }, status: :unprocessable_entity
      end

      private

      def parse_date(str)
        return nil unless str.present?
        Date.parse(str)
      rescue ArgumentError
        nil
      end

      # "09:00-12:00" を [start_time, end_time] に変換。不正なら nil を返す
      def parse_slots(slots)
        return nil unless slots.is_a?(Array)
        result = []
        slots.each do |s|
          return nil unless s.is_a?(String) && s.match?(/\A\d{1,2}:\d{2}-\d{1,2}:\d{2}\z/)
          start_str, end_str = s.split('-')
          result << [start_str, end_str]
        end
        result
      end

      def slots_json(slots)
        slots.map do |s|
          {
            id: s.id,
            start_time: s.start_time&.strftime('%H:%M'),
            end_time: s.end_time&.strftime('%H:%M'),
            slot_type: s.slot_type
          }
        end
      end
    end
  end
end
```

- [ ] **Step 3: テスト作成**

`test/controllers/api/v1/study_times_controller_test.rb` を作成：

```ruby
require "test_helper"

class Api::V1::StudyTimesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @student = users(:student_one)
    @token = @student.generate_api_token!
    @report = pdca_reports(:today_report)  # student_one's report on Date.today
  end

  test "create: 実績スロットを記録できる" do
    post "/api/v1/study_times",
      params: { date: @report.report_date.iso8601, slot_type: "actual", slots: ["09:00-12:00", "14:00-17:00"] },
      headers: api_headers(token: @token),
      as: :json

    assert_response :created
    assert_equal 2, json_response["actual_slots"].length
    assert_equal "09:00", json_response["actual_slots"][0]["start_time"]
    assert_equal "12:00", json_response["actual_slots"][0]["end_time"]
  end

  test "create: 報告が存在しない日は422を返す" do
    post "/api/v1/study_times",
      params: { date: "2020-01-01", slot_type: "actual", slots: ["09:00-12:00"] },
      headers: api_headers(token: @token),
      as: :json

    assert_response :unprocessable_entity
  end

  test "create: 不正な時間帯形式で400" do
    post "/api/v1/study_times",
      params: { date: @report.report_date.iso8601, slot_type: "actual", slots: ["invalid"] },
      headers: api_headers(token: @token),
      as: :json

    assert_response :bad_request
  end

  test "create: 実績を再記録すると古いスロットは削除される" do
    post "/api/v1/study_times",
      params: { date: @report.report_date.iso8601, slot_type: "actual", slots: ["09:00-12:00"] },
      headers: api_headers(token: @token), as: :json
    assert_response :created

    post "/api/v1/study_times",
      params: { date: @report.report_date.iso8601, slot_type: "actual", slots: ["13:00-15:00"] },
      headers: api_headers(token: @token), as: :json
    assert_response :created
    assert_equal 1, json_response["actual_slots"].length
    assert_equal "13:00", json_response["actual_slots"][0]["start_time"]
  end

  test "index: 学習時間を取得できる" do
    # データ作成
    post "/api/v1/study_times",
      params: { date: @report.report_date.iso8601, slot_type: "actual", slots: ["10:00-11:00"] },
      headers: api_headers(token: @token), as: :json

    get "/api/v1/study_times",
      params: { date: @report.report_date.iso8601 },
      headers: api_headers(token: @token)

    assert_response :success
    assert_equal 1, json_response["actual_slots"].length
    assert_equal [], json_response["planned_slots"]
  end

  test "index: date パラメータ未指定で400" do
    get "/api/v1/study_times", headers: api_headers(token: @token)
    assert_response :bad_request
  end

  test "認証なしは401" do
    get "/api/v1/study_times", params: { date: "2026-04-17" }
    assert_response :unauthorized
  end
end
```

**Note:** `pdca_reports(:report_one)` フィクスチャが存在しない場合、`test/fixtures/pdca_reports.yml` を確認して適切な名前に置き換える or 報告を setup 内で作成する。

- [ ] **Step 4: テスト実行**

```bash
bin/rails test test/controllers/api/v1/study_times_controller_test.rb 2>&1 | tail -5
```

Expected: 7 runs, 0 failures, 0 errors（もしフィクスチャ不整合でエラーが出たら、setupで動的に作成するよう調整）

- [ ] **Step 5: 構文チェック**

```bash
ruby -c app/controllers/api/v1/study_times_controller.rb
```

Expected: `Syntax OK`

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/study_times_controller.rb config/routes.rb test/controllers/api/v1/study_times_controller_test.rb
git commit -m "feat: 学習時間APIを追加 (#12)"
```

---

## Task 3: API - daily_goals_controller.rb 新規作成（E6 + S3）

**Files:**
- Create: `app/controllers/api/v1/daily_goals_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/daily_goals_controller_test.rb`

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: ルート追加**

`config/routes.rb` の v1 namespace 内に追加：

```ruby
resources :daily_goals, only: [:index] do
  resources :items, only: [:update], controller: "daily_goal_items"
end
```

ただし `items` を nested resource として扱うと URL 設計が冗長になるので、より素直に以下に変更する：

```ruby
get 'daily_goals', to: 'daily_goals#index'
patch 'daily_goals/:daily_goal_id/items/:id', to: 'daily_goals#update_item'
```

**選定**: 上記の **2行シンプル版** を採用する（新規コントローラー1本で完結）。

- [ ] **Step 2: Controller新規作成**

`app/controllers/api/v1/daily_goals_controller.rb` を作成：

```ruby
module Api
  module V1
    class DailyGoalsController < BaseController
      before_action :require_student!

      # GET /api/v1/daily_goals?date=YYYY-MM-DD
      # GET /api/v1/daily_goals?week=YYYY-MM-DD  (週頭日付)
      def index
        if params[:date].present?
          date = parse_date(params[:date])
          unless date
            render json: { error: 'date パラメータが不正です（例: 2026-04-17）' }, status: :bad_request
            return
          end

          daily_goal = current_user.daily_goals.for_date(date).first
          render json: { daily_goals: daily_goal ? [daily_goal_json(daily_goal)] : [] }
        elsif params[:week].present?
          week_start = parse_date(params[:week])
          unless week_start
            render json: { error: 'week パラメータが不正です（例: 2026-04-13）' }, status: :bad_request
            return
          end
          week_end = week_start + 6.days
          daily_goals = current_user.daily_goals.for_week(week_start, week_end).order(:goal_date).includes(:daily_goal_items)
          render json: { daily_goals: daily_goals.map { |d| daily_goal_json(d) } }
        else
          render json: { error: 'date または week パラメータが必要です' }, status: :bad_request
        end
      end

      # PATCH /api/v1/daily_goals/:daily_goal_id/items/:id
      # Body: { content: "新しいPlan内容" }
      def update_item
        daily_goal = current_user.daily_goals.find_by(id: params[:daily_goal_id])
        unless daily_goal
          render json: { error: '日次目標が見つかりません' }, status: :not_found
          return
        end

        item = daily_goal.daily_goal_items.find_by(id: params[:id])
        unless item
          render json: { error: '日次目標アイテムが見つかりません' }, status: :not_found
          return
        end

        if params[:content].blank?
          render json: { error: 'content が必要です' }, status: :bad_request
          return
        end

        if item.update(content: params[:content])
          render json: { item: item_json(item) }
        else
          render json: { error: 'バリデーションエラー', errors: item.errors.messages }, status: :unprocessable_entity
        end
      end

      private

      def parse_date(str)
        Date.parse(str)
      rescue ArgumentError, TypeError
        nil
      end

      def daily_goal_json(daily_goal)
        {
          id: daily_goal.id,
          goal_date: daily_goal.goal_date&.iso8601,
          weekly_goal_id: daily_goal.weekly_goal_id,
          items: daily_goal.learning_goal_items.map { |i| item_json(i) }
        }
      end

      def item_json(item)
        {
          id: item.id,
          content: item.content,
          progress: item.progress,
          position: item.position
        }
      end
    end
  end
end
```

- [ ] **Step 3: テスト作成**

`test/controllers/api/v1/daily_goals_controller_test.rb` を作成：

```ruby
require "test_helper"

class Api::V1::DailyGoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @student = users(:student_one)
    @token = @student.generate_api_token!
  end

  test "index: date 指定で日次目標を取得できる" do
    # 週次目標を作成して日次目標を自動生成
    wg = @student.weekly_goals.create!(week_start_date: Date.today.beginning_of_week(:monday), week_end_date: Date.today.beginning_of_week(:monday) + 6.days)
    wg.weekly_goal_items.create!(goal_type: "learning", content: "学習", position: 0, progress: 0)
    wg.generate_daily_goals

    target_date = wg.week_start_date
    get "/api/v1/daily_goals",
      params: { date: target_date.iso8601 },
      headers: api_headers(token: @token)

    assert_response :success
    assert_equal 1, json_response["daily_goals"].length
    assert_equal target_date.iso8601, json_response["daily_goals"][0]["goal_date"]
    assert json_response["daily_goals"][0]["items"].is_a?(Array)
  end

  test "index: 未存在日付は空配列" do
    get "/api/v1/daily_goals",
      params: { date: "2020-01-01" },
      headers: api_headers(token: @token)

    assert_response :success
    assert_equal [], json_response["daily_goals"]
  end

  test "index: week 指定で週単位一覧を取得" do
    wg = @student.weekly_goals.create!(week_start_date: Date.today.beginning_of_week(:monday), week_end_date: Date.today.beginning_of_week(:monday) + 6.days)
    wg.weekly_goal_items.create!(goal_type: "learning", content: "学習", position: 0, progress: 0)
    wg.generate_daily_goals

    get "/api/v1/daily_goals",
      params: { week: wg.week_start_date.iso8601 },
      headers: api_headers(token: @token)

    assert_response :success
    assert json_response["daily_goals"].length >= 1
  end

  test "index: date も week も未指定で400" do
    get "/api/v1/daily_goals", headers: api_headers(token: @token)
    assert_response :bad_request
  end

  test "update_item: content を更新できる" do
    wg = @student.weekly_goals.create!(week_start_date: Date.today.beginning_of_week(:monday), week_end_date: Date.today.beginning_of_week(:monday) + 6.days)
    wg.weekly_goal_items.create!(goal_type: "learning", content: "学習", position: 0, progress: 0)
    wg.generate_daily_goals

    daily_goal = @student.daily_goals.first
    item = daily_goal.daily_goal_items.first

    patch "/api/v1/daily_goals/#{daily_goal.id}/items/#{item.id}",
      params: { content: "新しいPlan" },
      headers: api_headers(token: @token), as: :json

    assert_response :success
    assert_equal "新しいPlan", json_response["item"]["content"]
    assert_equal "新しいPlan", item.reload.content
  end

  test "update_item: content が空ならエラー" do
    wg = @student.weekly_goals.create!(week_start_date: Date.today.beginning_of_week(:monday), week_end_date: Date.today.beginning_of_week(:monday) + 6.days)
    wg.weekly_goal_items.create!(goal_type: "learning", content: "学習", position: 0, progress: 0)
    wg.generate_daily_goals

    daily_goal = @student.daily_goals.first
    item = daily_goal.daily_goal_items.first

    patch "/api/v1/daily_goals/#{daily_goal.id}/items/#{item.id}",
      params: { content: "" },
      headers: api_headers(token: @token), as: :json

    assert_response :bad_request
  end

  test "update_item: 他人のアイテムは404" do
    other = users(:student_two)
    wg = other.weekly_goals.create!(week_start_date: Date.today.beginning_of_week(:monday), week_end_date: Date.today.beginning_of_week(:monday) + 6.days)
    wg.weekly_goal_items.create!(goal_type: "learning", content: "学習", position: 0, progress: 0)
    wg.generate_daily_goals

    daily_goal = other.daily_goals.first
    item = daily_goal.daily_goal_items.first

    patch "/api/v1/daily_goals/#{daily_goal.id}/items/#{item.id}",
      params: { content: "侵入" },
      headers: api_headers(token: @token), as: :json

    assert_response :not_found
  end

  test "認証なしは401" do
    get "/api/v1/daily_goals", params: { date: "2026-04-17" }
    assert_response :unauthorized
  end
end
```

- [ ] **Step 4: テスト実行**

```bash
bin/rails test test/controllers/api/v1/daily_goals_controller_test.rb 2>&1 | tail -5
```

Expected: 7 runs, 0 failures, 0 errors

- [ ] **Step 5: 構文チェック**

```bash
ruby -c app/controllers/api/v1/daily_goals_controller.rb
```

Expected: `Syntax OK`

- [ ] **Step 6: 全APIテスト実行（回帰確認）**

```bash
bin/rails test test/controllers/api/ 2>&1 | tail -5
```

Expected: 既存テスト + Task 2/3 新規テストすべて通過、0 failures

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/daily_goals_controller.rb config/routes.rb test/controllers/api/v1/daily_goals_controller_test.rb
git commit -m "feat: 日次目標の取得・更新APIを追加 (#10, #21)"
```

---

## Task 4: CLI - client.rb に新規メソッド群を追加

**Files:**
- Modify: `lib/pdca_cli/client.rb`

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: 新規メソッドを追加**

`lib/pdca_cli/client.rb` のclassの末尾（private直前、existingの `private` の前）に以下のメソッド群を追加。

まず `lib/pdca_cli/client.rb` の `private` 位置を特定：

```bash
grep -n "private" lib/pdca_cli/client.rb
```

その直前に以下を挿入：

```ruby
    # 学習時間（S5 / #12）
    def create_study_time(date:, slot_type: "actual", slots:)
      post("/api/v1/study_times", date: date, slot_type: slot_type, slots: slots)
    end

    def show_study_time(date:)
      get("/api/v1/study_times", date: date)
    end

    # 週次目標進捗更新（E8 / #32）
    # items: [{ id: 1, progress: 50 }, ...]
    def update_weekly_goal_items(id, items:)
      patch("/api/v1/weekly_goals/#{id}", items: items)
    end

    # 日次目標（E6 + S3 / #21, #10）
    def show_daily_goals(date: nil, week: nil)
      query = {}
      query[:date] = date if date
      query[:week] = week if week
      get("/api/v1/daily_goals", query)
    end

    def update_daily_goal_item(daily_goal_id:, item_id:, content:)
      patch("/api/v1/daily_goals/#{daily_goal_id}/items/#{item_id}", content: content)
    end
```

**注意:** `patch` HTTP メソッドは既に `lib/pdca_cli/client.rb:165` に定義済み。追加不要。

- [ ] **Step 2: 構文チェック**

```bash
ruby -c lib/pdca_cli/client.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/pdca_cli/client.rb
git commit -m "feat: 学習時間・日次目標・週次進捗%のクライアントメソッドを追加 (#12, #32, #21, #10)"
```

---

## Task 5: CLI - report create/update に --code / --code_file オプション追加（E9）

**Files:**
- Modify: `lib/pdca_cli/cli.rb` の `report create` (L71-112) と `report update` (L192付近)

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: `report create` にオプション追加**

`lib/pdca_cli/cli.rb` の `desc "create"` コマンドに、既存の `option :curriculum` の後に以下を追加：

```ruby
option :code, type: :string, desc: "提出コード内容（インライン）"
option :code_file, type: :string, desc: "提出コードをファイルから読み込む（--code と排他）"
```

`def create` の先頭（client.rb の前）で排他チェックと code 解決を行う：

```ruby
def create
  client = CLI.require_auth_from(self)

  if options[:code] && options[:code_file]
    CLI.error_output_from(self, "--code と --code_file は同時に指定できません")
    exit 2
  end

  resolved_code = resolve_code_option(options)

  # ...（既存の interactive / build_params_from_options 処理）
```

- [ ] **Step 2: `build_params_from_options` の拡張**

`build_params_from_options` を grep で探す：

```bash
grep -n "build_params_from_options\|def build_params" lib/pdca_cli/cli.rb
```

そのメソッド内で `curriculum_name` と `code_content` を params に含めるようにする：

```ruby
def build_params_from_options
  params = {
    report_date: options[:date] || Date.today.iso8601,
    learning_status: options[:status],
    learning_plan: options[:plan],
    learning_do: options[:do],
    learning_check: options[:check],
    learning_action: options[:action]
  }
  params[:curriculum_name] = options[:curriculum] if options[:curriculum]
  params[:code_content] = resolve_code_option(options) if options[:code] || options[:code_file]
  params.compact
end
```

**重要:** 既存の build_params_from_options の形状を壊さないこと。すでに curriculum_name が含まれているなら該当部分だけ追加。

- [ ] **Step 3: `resolve_code_option` ヘルパー追加**

CLI class の末尾（privateメソッド付近）に：

```ruby
def resolve_code_option(opts)
  return opts[:code] if opts[:code]
  return nil unless opts[:code_file]
  unless File.exist?(opts[:code_file])
    CLI.error_output_from(self, "--code_file で指定されたファイルが見つかりません: #{opts[:code_file]}")
    exit 2
  end
  File.read(opts[:code_file])
end
```

- [ ] **Step 4: `report update` にも同じオプションと処理を追加**

`desc "update"` のブロックに同じ option 定義と処理を追加。update は既存報告の該当フィールドのみ更新するため、buildメソッドも同様に拡張。

- [ ] **Step 5: 構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 6: Commit**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: report create/update にコード提出オプションを追加 (#33)"
```

---

## Task 6: CLI - print_report に code_content 表示を追加（E9）

**Files:**
- Modify: `lib/pdca_cli/cli.rb` の `print_report` メソッド

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: `print_report` の場所確認**

```bash
grep -n "def print_report" lib/pdca_cli/cli.rb
```

- [ ] **Step 2: code_content 表示を追加**

`print_report` メソッドの末尾（curriculum_name の表示後など）に以下を追加：

```ruby
if report["code_content"] && !report["code_content"].empty?
  code = report["code_content"]
  display_code = code.length > 200 ? "#{code[0..200]}...(省略)" : code
  say "Code:", :bold
  say display_code
end
```

- [ ] **Step 3: 構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 4: Commit**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: print_report にコード内容の表示を追加 (#33)"
```

---

## Task 7: CLI - goal progress サブコマンド（E8）

**Files:**
- Modify: `lib/pdca_cli/cli.rb` の `goal` サブコマンド内

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: goal サブコマンドの位置確認**

```bash
grep -n "subcommand \"goal\"" lib/pdca_cli/cli.rb
```

goal サブコマンド内の既存メソッド（update など）の近くに新規 `progress` コマンドを追加する。

- [ ] **Step 2: `progress` コマンド追加**

既存 `desc "update"` のすぐ後に追加（goal サブコマンドのブロック内）：

```ruby
      desc "progress", "週次目標アイテムの進捗%を変更"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :goal_id, type: :numeric, desc: "週次目標ID（省略時は現在の週の目標）"
      option :item_id, type: :numeric, desc: "対象アイテムID（単体更新時）"
      option :progress, type: :numeric, desc: "進捗% (0-100、単体更新時必須)"
      option :progresses, type: :array, desc: "一括更新 (例: \"5:50\" \"6:80\")"
      def progress
        client = CLI.require_auth_from(self)

        if options[:item_id] && options[:progresses]
          CLI.error_output_from(self, "--item_id/--progress と --progresses は同時に指定できません")
          exit 2
        end

        items = build_progress_items(options)
        if items.empty?
          CLI.error_output_from(self, "--item_id --progress か --progresses を指定してください")
          exit 2
        end

        # goal_id 解決
        goal_id = options[:goal_id]
        unless goal_id
          begin
            current_result = client.current_weekly_goal
            goal = current_result["weekly_goal"]
            if goal.nil?
              CLI.error_output_from(self, "現在の週の目標が見つかりません。--goal_id を指定してください")
              exit 2
            end
            goal_id = goal["id"]
          rescue Client::ApiError => e
            CLI.error_output_from(self, e.body["error"] || "週次目標の取得に失敗しました")
            exit 1
          end
        end

        begin
          result = client.update_weekly_goal_items(goal_id, items: items)
          if options[:json]
            say result.to_json
          else
            say "進捗を更新しました", :green
            (result["weekly_goal"]["items"] || []).each do |item|
              say "  ##{item['id']} [#{item['progress']}%] #{item['content']}"
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "進捗の更新に失敗しました")
          exit 1
        end
      end
```

**ヘルパーメソッド** を goal サブコマンド内に追加：

```ruby
      no_commands do
        def build_progress_items(opts)
          items = []
          if opts[:item_id] && opts[:progress]
            validate_progress_value(opts[:progress])
            items << { id: opts[:item_id], progress: opts[:progress] }
          end
          if opts[:progresses]
            opts[:progresses].each do |pair|
              unless pair =~ /\A(\d+):(\d{1,3})\z/
                CLI.error_output_from(self, "--progresses の形式が不正です（例: \"5:50\"）: #{pair}")
                exit 2
              end
              id = $1.to_i
              progress = $2.to_i
              validate_progress_value(progress)
              items << { id: id, progress: progress }
            end
          end
          items
        end

        def validate_progress_value(value)
          unless (0..100).cover?(value)
            CLI.error_output_from(self, "進捗は0〜100の範囲で指定してください（指定値: #{value}）")
            exit 2
          end
        end
      end
```

- [ ] **Step 3: 構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 4: Commit**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: goal progress コマンドで週次目標の進捗%を変更可能に (#32)"
```

---

## Task 8: CLI - study サブコマンド（S5）

**Files:**
- Modify: `lib/pdca_cli/cli.rb` に `study` サブコマンドを追加

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: study サブコマンド追加**

`lib/pdca_cli/cli.rb` 内の他のサブコマンド定義（例: `subcommand "plan"`, `subcommand "goal"` など）の近くに、以下を追加：

```ruby
    desc "study SUBCOMMAND", "学習時間の管理"
    subcommand "study", Class.new(Thor) { @_thor_name = "pdca study"

      desc "log", "学習時間の実績を記録"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, desc: "対象日 (YYYY-MM-DD, デフォルト: 今日)"
      option :slots, type: :array, required: true, desc: "時間帯 (例: \"09:00-12:00\" \"14:00-17:00\")"
      def log
        client = CLI.require_auth_from(self)
        date = options[:date] || Date.today.iso8601

        # 時間帯の形式チェック
        options[:slots].each do |s|
          unless s =~ /\A\d{1,2}:\d{2}-\d{1,2}:\d{2}\z/
            CLI.error_output_from(self, "時間帯の形式が不正です（例: \"09:00-12:00\"）: #{s}")
            exit 2
          end
        end

        begin
          result = client.create_study_time(date: date, slot_type: "actual", slots: options[:slots])
          if options[:json]
            say result.to_json
          else
            say "学習時間を記録しました (#{date})", :green
            (result["actual_slots"] || []).each do |slot|
              say "  #{slot['start_time']} - #{slot['end_time']}"
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "学習時間の保存に失敗しました")
          exit (e.status == 422 ? 2 : 1)
        end
      end

      desc "show", "学習時間を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, desc: "対象日 (YYYY-MM-DD, デフォルト: 今日)"
      def show
        client = CLI.require_auth_from(self)
        date = options[:date] || Date.today.iso8601

        begin
          result = client.show_study_time(date: date)
          if options[:json]
            say result.to_json
          else
            say "学習時間 (#{date})", :bold
            say "  予定:"
            (result["planned_slots"] || []).each { |s| say "    #{s['start_time']} - #{s['end_time']}" }
            say "  実績:"
            (result["actual_slots"] || []).each { |s| say "    #{s['start_time']} - #{s['end_time']}" }
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "学習時間の取得に失敗しました")
          exit (e.status == 404 ? 2 : 1)
        end
      end
    }
```

- [ ] **Step 2: 構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: study サブコマンド（実績記録・表示）を追加 (#12)"
```

---

## Task 9: CLI - daily サブコマンド（E6 + S3）

**Files:**
- Modify: `lib/pdca_cli/cli.rb` に `daily` サブコマンドを追加

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: daily サブコマンド追加**

他のサブコマンドの近くに追加：

```ruby
    desc "daily SUBCOMMAND", "日次目標の管理"
    subcommand "daily", Class.new(Thor) { @_thor_name = "pdca daily"

      desc "show", "指定日の日次目標を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, desc: "対象日 (YYYY-MM-DD, デフォルト: 今日)"
      def show
        client = CLI.require_auth_from(self)
        date = options[:date] || Date.today.iso8601

        begin
          result = client.show_daily_goals(date: date)
          daily_goals = result["daily_goals"] || []
          if options[:json]
            say result.to_json
          elsif daily_goals.empty?
            say "日次目標が見つかりません (#{date})", :yellow
          else
            dg = daily_goals.first
            say "日次目標 (#{dg['goal_date']})", :bold
            (dg["items"] || []).each do |item|
              say "  ##{item['id']} [#{item['progress']}%] #{item['content']}"
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "日次目標の取得に失敗しました")
          exit 1
        end
      end

      desc "list", "週単位で日次目標一覧を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :week, type: :string, required: true, desc: "週頭日 (YYYY-MM-DD)"
      def list
        client = CLI.require_auth_from(self)
        begin
          result = client.show_daily_goals(week: options[:week])
          daily_goals = result["daily_goals"] || []
          if options[:json]
            say result.to_json
          elsif daily_goals.empty?
            say "日次目標が見つかりません", :yellow
          else
            daily_goals.each do |dg|
              say "#{dg['goal_date']}", :bold
              (dg["items"] || []).each do |item|
                say "  ##{item['id']} [#{item['progress']}%] #{item['content']}"
              end
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "日次目標一覧の取得に失敗しました")
          exit 1
        end
      end

      desc "update", "日次目標アイテムの Plan 内容を更新"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, required: true, desc: "対象日 (YYYY-MM-DD)"
      option :plans, type: :array, required: true, desc: "更新内容 (例: \"101=Ruby基礎\" \"102=hash演習\")"
      def update
        client = CLI.require_auth_from(self)

        # 対象日の daily_goal_id を取得
        begin
          lookup = client.show_daily_goals(date: options[:date])
          daily_goals = lookup["daily_goals"] || []
          if daily_goals.empty?
            CLI.error_output_from(self, "#{options[:date]} の日次目標が見つかりません")
            exit 2
          end
          daily_goal_id = daily_goals.first["id"]
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "日次目標の取得に失敗しました")
          exit 1
        end

        # --plans の解析
        updates = []
        options[:plans].each do |pair|
          unless pair.include?("=")
            CLI.error_output_from(self, "--plans の形式が不正です（例: \"101=内容\"）: #{pair}")
            exit 2
          end
          item_id, content = pair.split("=", 2)
          if item_id.to_i.to_s != item_id || content.to_s.empty?
            CLI.error_output_from(self, "--plans の形式が不正です（例: \"101=内容\"）: #{pair}")
            exit 2
          end
          updates << { item_id: item_id.to_i, content: content }
        end

        # 1件ずつPATCH
        results = []
        updates.each do |u|
          begin
            r = client.update_daily_goal_item(daily_goal_id: daily_goal_id, item_id: u[:item_id], content: u[:content])
            results << r["item"]
          rescue Client::ApiError => e
            CLI.error_output_from(self, e.body["error"] || "アイテム #{u[:item_id]} の更新に失敗しました")
            exit 1
          end
        end

        if options[:json]
          say ({ items: results }).to_json
        else
          say "日次目標を更新しました (#{options[:date]})", :green
          results.each { |item| say "  ##{item['id']} #{item['content']}" }
        end
      end
    }
```

- [ ] **Step 2: 構文チェック**

```bash
ruby -c lib/pdca_cli/cli.rb
```

Expected: `Syntax OK`

- [ ] **Step 3: Commit**

```bash
git add lib/pdca_cli/cli.rb
git commit -m "feat: daily サブコマンド（日次目標のshow/list/update）を追加 (#10, #21)"
```

---

## Task 10: CLI - CLAUDE.md 更新（全機能）

**Files:**
- Modify: `CLAUDE.md`

**作業ディレクトリ:** `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: 全機能のコマンドを CLAUDE.md に追加**

CLAUDE.md の既存「## 主要コマンド」セクション内に、以下のサブセクションを追加（適切な位置に）：

```markdown
### 日次目標（S3 + E6）
\`\`\`bash
# 指定日の日次目標を表示
bin/pdca daily show --date 2026-04-17 --json

# 週単位で一覧
bin/pdca daily list --week 2026-04-13 --json

# アイテムの Plan 内容を更新（id=内容 形式、最初の = で分割）
bin/pdca daily update --date 2026-04-17 --plans "101=Ruby配列" "102=hash演習" --json
\`\`\`

### 学習時間（S5）
\`\`\`bash
# 実績の記録
bin/pdca study log --date 2026-04-17 --slots "09:00-12:00" "14:00-17:00" --json

# 学習時間を表示（予定・実績両方）
bin/pdca study show --date 2026-04-17 --json
\`\`\`

### 週次目標進捗%（E8）
\`\`\`bash
# 単体更新（現在の週の目標が自動選択される）
bin/pdca goal progress --item_id 5 --progress 50 --json

# 一括更新
bin/pdca goal progress --progresses "5:50" "6:80" --json
\`\`\`

### コード提出（E9）
\`\`\`bash
# 作成時にコード添付
bin/pdca report create --status green --plan "..." --curriculum "Ruby基礎" --code "def hello; end" --json

# ファイルから読み込み
bin/pdca report create --plan "..." --curriculum "Ruby基礎" --code_file ./solution.rb --json

# 更新時も同様
bin/pdca report update --date 2026-04-17 --code "新しいコード" --json
\`\`\`
```

- [ ] **Step 2: 注意事項セクションを更新**

既存「## 注意事項」に以下を追加：

```markdown
- `--code` と `--code_file` は排他。両方指定するとエラー
- `daily update --plans` は `id=内容` 形式。最初の `=` で分割するため、内容に `=` や `:` を含められる
- `study log` は実績(actual)のみ対応。予定(planned)はWeb側から入力
- `goal progress` は `--item_id + --progress`（単体）か `--progresses "id:%"`（一括）のどちらか一方を指定
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: 新機能（学習時間/進捗%/コード提出/日次目標）の使用例を追記 (#10, #12, #21, #32, #33)"
```

---

## Task 11: ローカル動作確認

**作業ディレクトリ:**
- CLI: `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`
- API: `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features`

**前提:** API側の development DB を worktree の `storage/development.sqlite3` にコピー済み（`/Users/iwakirikoudou/Desktop/occ_pdca_app/storage/development.sqlite3` から）。

- [ ] **Step 1: DBをコピーしてAPIサーバー起動**

```bash
cp ~/Desktop/occ_pdca_app/storage/development.sqlite3 ~/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features/storage/development.sqlite3
cd ~/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features && RAILS_ENV=development bin/rails server -p 3001 &
```

約10秒待って `curl -s http://localhost:3001/up` で起動確認。

- [ ] **Step 2: 受講生トークン取得**

```bash
cd ~/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features && RAILS_ENV=development bin/rails runner 'u = User.where(role: "student").first; puts "ID=#{u.id} NAME=#{u.name}"; puts "TOKEN=#{u.generate_api_token!}"'
```

**出力例:**
```
ID=3 NAME=受講生1
TOKEN=xxxxxxxx
```

- [ ] **Step 3: ヘルプ確認（各コマンドのオプション反映）**

```bash
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca study log --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca study show --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily show --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily list --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily update --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca goal progress --help
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca report create --help | grep -E "code|curriculum"
```

Expected: 各コマンドで期待するオプションが表示される。

- [ ] **Step 4: ① 学習時間（S5）動作確認**

```bash
# 先に今日の report を作成（すでに存在するならスキップ）
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca report today --json

# 学習時間を記録（今日分）
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca study log --slots "09:00-12:00" "14:00-17:00" --json

# 確認
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca study show --json
```

Expected: `actual_slots` に 2 件のスロットが返る。

- [ ] **Step 5: ② 週次進捗%（E8）動作確認**

```bash
# 現在の週次目標確認（item_id取得）
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca goal current --json

# 進捗更新（上記で得た item_id を使う）
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca goal progress --item_id <ID> --progress 50 --json

# 一括更新
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca goal progress --progresses "<ID>:80" --json
```

Expected: 該当 item の progress が更新されること。

- [ ] **Step 6: ③ コード提出（E9）動作確認**

```bash
# インラインコード提出
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca report update --date $(date +%Y-%m-%d) --curriculum "Ruby基礎" --code "def hello; puts 'hi'; end" --json

# 表示（code_content が含まれているか）
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca report today --json | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print('curriculum:', d['report']['curriculum_name']); print('code:', d['report']['code_content'])"

# ファイル読み込み
echo 'class Foo; end' > /tmp/test_code.rb
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca report update --date $(date +%Y-%m-%d) --code_file /tmp/test_code.rb --json
```

Expected: curriculum_name と code_content が正しく保存・取得できる。

- [ ] **Step 7: ④ 日次目標（E6 + S3）動作確認**

```bash
# 現在の週次目標 → 日次目標を自動生成済みのはず
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily show --json

# item_id 取得して更新
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily update --date $(date +%Y-%m-%d) --plans "<ITEM_ID>=更新した内容: コロン入り" --json

# 週単位一覧
PDCA_API_URL=http://localhost:3001 PDCA_TOKEN=<token> bin/pdca daily list --week $(date -v -mon +%Y-%m-%d) --json
```

Expected: content が更新され、list でも反映されている。

- [ ] **Step 8: APIサーバー停止**

```bash
pkill -f "rails server -p 3001" 2>/dev/null
```

---

## Task 12: 両リポジトリに PR 作成

**作業ディレクトリ:**
- CLI: `/Users/iwakirikoudou/Desktop/pdca-cli/.claude/worktrees/urgent-student-features`
- API: `/Users/iwakirikoudou/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features`

- [ ] **Step 1: API側を push**

```bash
cd ~/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features
git push -u origin feature/urgent-student-features
```

- [ ] **Step 2: API側PR作成**

```bash
gh pr create --title "feat: 受講生向け急ぎ機能バンドル（学習時間/日次目標API + code_content対応）" --body "$(cat <<'EOF'
## 概要

本家学習媒体のドリル対応要件に連動した受講生向けCLI機能の API 側対応。

### 関連Issue
- #10 S3: 日次目標管理（index/update）
- #12 S5: 学習時間記録（実績）
- #21 E6: 日次目標のPlan変更
- #32 E8: 週次目標の進捗%変更（※CLI側のみ変更）
- #33 E9: PDCA報告のコード提出対応

### CLI側PR
（CLI側PR作成後にURL追記）

## 変更内容
- `app/controllers/api/v1/reports_controller.rb`: `report_json` に `code_content` を1行追加
- `app/controllers/api/v1/study_times_controller.rb`: 新規
- `app/controllers/api/v1/daily_goals_controller.rb`: 新規
- `config/routes.rb`: 上記2ルート追加
- Minitest テスト +14件（学習時間7 + 日次目標7）

### E8 のAPI側変更について
`weekly_goals_controller#update` が既に `progress` の permit に対応していたため、本PRでは変更なし。CLI側のみで実装完結。

## テスト結果
（実装後にテスト実行結果を記載）

## マージ順序
本PR → マージ・デプロイ → CLI側PR の順。
EOF
)"
```

- [ ] **Step 3: CLI側を push**

```bash
cd ~/Desktop/pdca-cli/.claude/worktrees/urgent-student-features
git push -u origin feature/urgent-student-features
```

- [ ] **Step 4: CLI側PR作成**

```bash
gh pr create --title "feat: 受講生向け急ぎ機能バンドル（学習時間/進捗%/コード提出/日次目標）" --body "$(cat <<'EOF'
## 概要

本家学習媒体のドリル対応要件に連動した受講生向けCLI機能を4つまとめて追加。

### 関連Issue
- #10 S3: 日次目標管理（CLI new command `daily`）
- #12 S5: 学習時間記録（CLI new command `study`）
- #21 E6: 日次目標のPlan変更（CLI `daily update`）
- #32 E8: 週次目標の進捗%変更（CLI new command `goal progress`）
- #33 E9: PDCA報告のコード提出（`report create/update` に `--code`/`--code_file`/`--curriculum`）

### API側PR
（API側PR URL を追記）

## 変更内容
- `lib/pdca_cli/client.rb`: 5メソッド追加（study / daily / goal_progress 系）
- `lib/pdca_cli/cli.rb`:
  - 新規 `study` サブコマンド（log/show）
  - 新規 `daily` サブコマンド（show/list/update）
  - 新規 `goal progress` サブコマンド
  - 既存 `report create/update` に `--code`/`--code_file`/`--curriculum` 追加
  - `print_report` にコード内容表示を追加
- `CLAUDE.md`: 全機能の使用例と注意事項追加

## Test plan
ローカル環境（Rails サーバー :3001 + sqlite dev DB）で動作確認済み：
- [x] `bin/pdca study log/show` 動作確認
- [x] `bin/pdca goal progress --item_id/--progresses` 動作確認
- [x] `bin/pdca report create/update --code/--code_file/--curriculum` 動作確認
- [x] `bin/pdca daily show/list/update` 動作確認

## マージ順序
API側PR がマージ・デプロイされてからマージしてください。順序を守らないと、新CLIが旧APIを叩いて機能が動作しません。

## テスト方針
既存プロジェクトにテスト依存が無いため CLI 側は手動動作確認で検証。API 側では +14 件のMinitestを追加済み。
EOF
)"
```

- [ ] **Step 5: 相互リンク更新**

両PRの body に相互リンクを追加：

```bash
# API側PR の body を更新（CLI側PRのURLを取得してから）
CLI_PR=$(gh pr view --json url -q .url --repo koki-kato/pdca-cli)
cd ~/Desktop/occ_pdca_app/.claude/worktrees/urgent-student-features
gh pr edit <API_PR_NUM> --body "$(gh pr view <API_PR_NUM> --json body -q .body | sed "s|（CLI側PR作成後にURL追記）|$CLI_PR|")"

# CLI側PR の body を更新
cd ~/Desktop/pdca-cli/.claude/worktrees/urgent-student-features
gh pr edit <CLI_PR_NUM> --body "$(gh pr view <CLI_PR_NUM> --json body -q .body | sed "s|（API側PR URL を追記）|<API_PR_URL>|")"
```

---

## 完了基準

- [ ] Task 1-12 の全ステップが完了
- [ ] API側テスト全通過（既存+新規14件）
- [ ] ローカル動作確認で4機能全て動作
- [ ] API側 / CLI側の両PRが作成され相互リンクされている
- [ ] 対応Issue（#10, #12, #21, #32, #33）をPR本文に記載
