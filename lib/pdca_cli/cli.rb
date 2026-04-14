require "thor"
require "date"
require "json"

module PdcaCli
  class CLI < Thor
    desc "login", "PDCA報告サーバーにログイン"
    option :json, type: :boolean, default: false, desc: "JSON形式で出力"
    def login
      config = Config.new
      interactive = Interactive.new(self)
      params = interactive.ask_login_params(current_api_url: config.api_url)

      unless params[:api_url] && !params[:api_url].empty?
        error_output("API URLを入力してください")
        exit 1
      end

      client = Client.new(api_url: params[:api_url])

      begin
        result = client.login(email: params[:email], password: params[:password])
        config.api_url = params[:api_url]
        config.token = result["token"]
        config.save!

        user = result["user"]
        if options[:json]
          say result.to_json
        else
          say "ログイン成功！ (#{user['name']} さん)", :green
          say "設定を ~/.pdca.yml に保存しました。"
        end
      rescue Client::ApiError => e
        error_output(e.body["error"] || "ログインに失敗しました")
        exit 1
      end
    end

    desc "logout", "ログアウト（トークンを削除）"
    def logout
      config = Config.new
      config.clear!
      say "ログアウトしました。", :green
    end

    desc "whoami", "現在のログインユーザー情報を表示"
    option :json, type: :boolean, default: false, desc: "JSON形式で出力"
    def whoami
      client = require_auth!

      begin
        result = client.me
        user = result["user"]

        if options[:json]
          say result.to_json
        else
          say "ユーザー: #{user['name']} (#{user['email']})"
          say "ロール:   #{user['role']}"
        end
      rescue Client::ApiError => e
        error_output(e.body["error"] || "ユーザー情報の取得に失敗しました")
        exit 1
      end
    end

    desc "report SUBCOMMAND", "PDCA報告の操作"
    subcommand "report", Class.new(Thor) { @_thor_name = "pdca report"

      desc "create", "PDCA報告を作成"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, desc: "報告日 (YYYY-MM-DD, デフォルト: 今日)"
      option :status, type: :string, desc: "学習状況 (green/yellow/red)"
      option :plan, type: :string, desc: "Plan: 学習計画"
      option :do, type: :string, desc: "Do: 実施内容"
      option :check, type: :string, desc: "Check: 振り返り"
      option :action, type: :string, desc: "Action: 次のアクション"
      option :curriculum, type: :string, desc: "カリキュラム名"
      def create
        client = CLI.require_auth_from(self)

        # フラグが指定されていれば直接実行、なければ対話型
        if options[:status] || options[:plan]
          params = build_params_from_options
        else
          interactive = Interactive.new(self)
          params = interactive.ask_report_params
          exit 0 if params.nil?
        end

        begin
          result = client.create_report(params)
          report = result["report"]

          if options[:json]
            say result.to_json
          else
            say "PDCA報告を作成しました (ID: #{report['id']})", :green
            print_report(report)
          end
        rescue Client::ApiError => e
          body = e.body
          if e.status == 422 && body["errors"]
            error_msg = body["errors"].map { |k, v| "#{k}: #{v.join(', ')}" }.join("\n")
            CLI.error_output_from(self, "バリデーションエラー\n#{error_msg}")
          else
            CLI.error_output_from(self, body["error"] || "報告の作成に失敗しました")
          end
          exit 2
        end
      end

      desc "today", "今日の報告を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      def today
        client = CLI.require_auth_from(self)

        begin
          result = client.today_report
          report = result["report"]

          if options["json"]
            say result.to_json
          elsif report
            print_report(report)
          else
            say "今日の報告はまだありません。", :yellow
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "報告の取得に失敗しました")
          exit 1
        end
      end

      desc "show", "指定日の報告を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, required: true, desc: "報告日 (YYYY-MM-DD)"
      def show
        client = CLI.require_auth_from(self)

        begin
          result = client.report_by_date(options[:date])
          report = result["report"]

          if options[:json]
            say result.to_json
          elsif report
            print_report(report)
          else
            say "#{options[:date]} の報告はありません。", :yellow
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "報告の取得に失敗しました")
          exit 1
        end
      end

      desc "list", "報告一覧を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :month, type: :string, desc: "月指定 (YYYY-MM)"
      option :limit, type: :numeric, default: 10, desc: "表示件数"
      def list
        client = CLI.require_auth_from(self)

        begin
          result = client.list_reports(month: options[:month], limit: options[:limit])
          reports = result["reports"]

          if options[:json]
            say result.to_json
          elsif reports.empty?
            say "報告がありません。", :yellow
          else
            reports.each do |report|
              status_icon = case report["learning_status"]
                            when "green" then "G"
                            when "yellow" then "Y"
                            when "red" then "R"
                            else "-"
                            end
              plan = (report["learning_plan"] || "")[0..40]
              say "#{report['report_date']}  [#{status_icon}]  #{plan}"
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "報告一覧の取得に失敗しました")
          exit 1
        end
      end

      desc "update", "報告を更新"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :date, type: :string, required: true, desc: "報告日 (YYYY-MM-DD)"
      option :status, type: :string, desc: "学習状況 (green/yellow/red)"
      option :plan, type: :string, desc: "Plan: 学習計画"
      option :do, type: :string, desc: "Do: 実施内容"
      option :check, type: :string, desc: "Check: 振り返り"
      option :action, type: :string, desc: "Action: 次のアクション"
      def update
        client = CLI.require_auth_from(self)

        # まず日付で報告を検索
        begin
          result = client.report_by_date(options[:date])
          report = result["report"]

          unless report
            CLI.error_output_from(self, "#{options[:date]} の報告が見つかりません。先にcreateしてください。")
            exit 2
          end

          params = build_params_from_options
          params.delete(:report_date)

          result = client.update_report(report["id"], params)
          updated = result["report"]

          if options[:json]
            say result.to_json
          else
            say "報告を更新しました (ID: #{updated['id']})", :green
            print_report(updated)
          end
        rescue Client::ApiError => e
          body = e.body
          if e.status == 422 && body["errors"]
            error_msg = body["errors"].map { |k, v| "#{k}: #{v.join(', ')}" }.join("\n")
            CLI.error_output_from(self, "バリデーションエラー\n#{error_msg}")
          else
            CLI.error_output_from(self, body["error"] || "報告の更新に失敗しました")
          end
          exit 2
        end
      end

      no_commands do
        def print_report(report)
          status_label = case report["learning_status"]
                         when "green" then "green (順調)"
                         when "yellow" then "yellow (少し詰まっている)"
                         when "red" then "red (止まっている)"
                         else "(未設定)"
                         end
          say ""
          say "日付:   #{report['report_date']}"
          say "状況:   #{status_label}"
          say "Plan:   #{report['learning_plan'] || '(未入力)'}"
          say "Do:     #{report['learning_do'] || '(未入力)'}"
          say "Check:  #{report['learning_check'] || '(未入力)'}"
          say "Action: #{report['learning_action'] || '(未入力)'}"
        end

        def build_params_from_options
          params = {}
          params[:report_date] = options[:date] || Date.today.iso8601
          params[:learning_status] = options[:status] if options[:status]
          params[:learning_plan] = options[:plan] if options[:plan]
          params[:learning_do] = options[:do] if options[:do]
          params[:learning_check] = options[:check] if options[:check]
          params[:learning_action] = options[:action] if options[:action]
          params[:curriculum_name] = options[:curriculum] if options[:curriculum]
          params
        end
      end
    }

    desc "plan SUBCOMMAND", "学習計画の操作"
    subcommand "plan", Class.new(Thor) { @_thor_name = "pdca plan"

      desc "show", "学習計画を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      def show
        client = CLI.require_auth_from(self)

        begin
          result = client.get_plan
          plan = result["plan"]

          if options[:json]
            say result.to_json
          elsif plan
            print_plan(plan)
          else
            say "学習計画がまだ設定されていません。", :yellow
            say "`pdca plan setup` で設定してください。"
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "学習計画の取得に失敗しました")
          exit 1
        end
      end

      desc "setup", "学習計画を新規作成"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :name, type: :string, desc: "コース名"
      option :categories, type: :array, desc: "カテゴリリスト（スペース区切り）"
      def setup
        client = CLI.require_auth_from(self)

        course_name = options[:name]
        categories = options[:categories]

        # 対話型
        unless categories && !categories.empty?
          say ""
          say "学習計画を設定します", :bold
          say ""
          course_name ||= ask("コース名 (例: Ruby on Rails学習):")
          course_name = "学習計画" if course_name.nil? || course_name.strip.empty?

          say ""
          say "カリキュラムのカテゴリを入力してください（最大10個、空欄で終了）"
          categories = []
          (1..10).each do |i|
            input = ask("カテゴリ#{i}:")
            break if input.nil? || input.strip.empty?
            # "カテゴリ名:時間" 形式に対応
            parts = input.strip.split(":", 2)
            if parts.length == 2 && parts[1].strip.match?(/^\d+(\.\d+)?$/)
              categories << { name: parts[0].strip, estimated_hours: parts[1].strip.to_f }
            else
              categories << { name: input.strip, estimated_hours: 0 }
            end
          end

          if categories.empty?
            say "カテゴリが入力されませんでした。", :yellow
            exit 0
          end

          say ""
          say "--- 確認 ---"
          say "コース: #{course_name}"
          categories.each_with_index do |c, i|
            name = c.is_a?(Hash) ? c[:name] : c
            hours = c.is_a?(Hash) ? c[:estimated_hours] : 0
            hours_label = hours > 0 ? " (#{hours}h)" : ""
            say "  #{i + 1}. #{name}#{hours_label}"
          end
          say ""
          unless yes?("設定しますか？ [Y/n]")
            say "キャンセルしました。", :yellow
            exit 0
          end
        end

        begin
          result = client.setup_plan(course_name: course_name, categories: categories)
          plan = result["plan"]

          if options[:json]
            say result.to_json
          else
            say "学習計画を作成しました", :green
            print_plan(plan)
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "学習計画の作成に失敗しました")
          exit 2
        end
      end

      desc "add", "カテゴリを追加"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :name, type: :string, desc: "カテゴリ名"
      option :hours, type: :numeric, default: 0, desc: "目安時間（時間）"
      def add
        client = CLI.require_auth_from(self)

        name = options[:name]
        unless name
          name = ask("カテゴリ名:")
        end

        begin
          result = client.add_plan_category(name: name, estimated_hours: options[:hours])

          if options[:json]
            say result.to_json
          else
            say "カテゴリを追加しました: #{name}", :green
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "カテゴリの追加に失敗しました")
          exit 2
        end
      end

      no_commands do
        def print_plan(plan)
          say ""
          say "コース: #{plan['course_name']}"
          progress = plan["progress"]
          say "進捗: #{progress['completed']}/#{progress['total']} (#{progress['percentage']}%)"
          say ""
          plan["categories"].each_with_index do |cat, i|
            status = cat["completed"] ? "[x]" : "[ ]"
            hours_label = cat["estimated_hours"] > 0 ? " (#{cat['estimated_hours']}h)" : ""
            say "  #{status} #{i + 1}. #{cat['name']}#{hours_label}"
          end
        end
      end
    }

    desc "goal SUBCOMMAND", "週次目標の操作"
    subcommand "goal", Class.new(Thor) { @_thor_name = "pdca goal"

      desc "current", "今週の目標を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      def current
        client = CLI.require_auth_from(self)

        begin
          result = client.current_weekly_goal
          goal = result["weekly_goal"]

          if options[:json]
            say result.to_json
          elsif goal
            print_goal(goal)
          else
            say "今週の目標はまだ設定されていません。", :yellow
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "目標の取得に失敗しました")
          exit 1
        end
      end

      desc "list", "週次目標の一覧を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :limit, type: :numeric, default: 5, desc: "表示件数"
      def list
        client = CLI.require_auth_from(self)

        begin
          result = client.list_weekly_goals(limit: options[:limit])
          goals = result["weekly_goals"]

          if options[:json]
            say result.to_json
          elsif goals.empty?
            say "週次目標がありません。", :yellow
          else
            goals.each do |goal|
              items_summary = goal["items"].map { |i| i["content"] }.join(", ")
              items_summary = items_summary[0..50] + "..." if items_summary.length > 50
              say "#{goal['week_start_date']} ~ #{goal['week_end_date']}  [#{goal['completion_rate']}%]  #{items_summary}"
            end
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "目標一覧の取得に失敗しました")
          exit 1
        end
      end

      desc "create", "週次目標を作成（学習計画から選択 or 自由入力）"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :week_start, type: :string, desc: "週の開始日 (YYYY-MM-DD, デフォルト: 今週)"
      option :items, type: :array, desc: "目標リスト（スペース区切り）"
      option :category_ids, type: :array, desc: "カテゴリIDリスト（学習計画から選択）"
      option :force, type: :boolean, default: false, desc: "既存の目標を上書きする"
      def create
        client = CLI.require_auth_from(self)

        items = nil

        # --category_ids が指定された場合
        if options[:category_ids]
          plan_result = client.get_plan
          plan = plan_result["plan"]
          unless plan
            CLI.error_output_from(self, "学習計画がありません。先に `pdca plan setup` を実行してください。")
            exit 2
          end
          categories = plan["categories"]
          items = options[:category_ids].map { |cid|
            cat = categories.find { |c| c["id"].to_s == cid.to_s }
            if cat
              { content: cat["name"], category_id: cat["id"] }
            else
              CLI.error_output_from(self, "カテゴリID #{cid} が見つかりません。")
              exit 2
            end
          }
        # --items が指定された場合
        elsif options[:items] && !options[:items].empty?
          items = options[:items]
        end

        # フラグなしなら対話型
        unless items
          say ""
          say "週次目標を設定します", :bold
          week_label = options[:week_start] || "今週"
          say "対象: #{week_label}"

          # 学習計画があればカテゴリから選択可能
          plan_result = client.get_plan rescue nil
          plan = plan_result&.dig("plan")

          if plan && plan["categories"] && !plan["categories"].empty?
            categories = plan["categories"].reject { |c| c["completed"] }
            if categories.any?
              say ""
              say "学習計画のカテゴリから選択できます:"
              categories.each_with_index do |cat, i|
                hours_label = cat["estimated_hours"] > 0 ? " (#{cat['estimated_hours']}h)" : ""
                say "  #{i + 1}. #{cat['name']}#{hours_label}"
              end
              say ""
              selection = ask("番号を選択（カンマ区切りで複数可、空欄で自由入力）:")

              if selection && !selection.strip.empty?
                indices = selection.split(",").map { |s| s.strip.to_i - 1 }
                items = indices.filter_map { |idx|
                  cat = categories[idx]
                  next unless cat
                  { content: cat["name"], category_id: cat["id"] }
                }
              end
            end
          end

          # カテゴリから選択しなかった場合は自由入力
          unless items && !items.empty?
            say ""
            items = []
            (1..3).each do |i|
              item = ask("目標#{i} (空欄で終了):")
              break if item.nil? || item.strip.empty?
              items << item.strip
            end
          end

          if items.empty?
            say "目標が入力されませんでした。", :yellow
            exit 0
          end

          if options[:force]
            say "⚠ 既存の週次目標が削除されます。", :yellow
            unless yes?("続行しますか？ [Y/n]")
              say "キャンセルしました。", :yellow
              exit 0
            end
          end

          say ""
          say "--- 確認 ---"
          items.each_with_index do |item, i|
            label = item.is_a?(Hash) ? item[:content] : item
            say "#{i + 1}. #{label}"
          end
          say ""
          unless yes?("設定しますか？ [Y/n]")
            say "キャンセルしました。", :yellow
            exit 0
          end
        end

        begin
          result = client.create_weekly_goal(items: items, week_start: options[:week_start], force: options[:force])
          goal = result["weekly_goal"]

          if options[:json]
            say result.to_json
          else
            say "週次目標を作成しました", :green
            print_goal(goal)
          end
        rescue Client::ApiError => e
          body = e.body
          if e.status == 409
            CLI.error_output_from(self, "この週の目標は既に設定されています。上書きするには --force オプションを使用してください。")
          elsif e.status == 422 && body["errors"]
            error_msg = body["errors"].map { |k, v| "#{k}: #{v.join(', ')}" }.join("\n")
            CLI.error_output_from(self, "バリデーションエラー\n#{error_msg}")
          else
            CLI.error_output_from(self, body["error"] || "目標の作成に失敗しました")
          end
          exit 2
        end
      end

      desc "update", "週次目標の進捗・内容を更新"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      def update
        client = CLI.require_auth_from(self)

        begin
          # まず今週の目標を取得
          result = client.current_weekly_goal
          goal = result["weekly_goal"]

          unless goal
            CLI.error_output_from(self, "今週の目標がありません。先にcreateしてください。")
            exit 2
          end

          items = goal["items"]
          say ""
          say "週次目標を更新します", :bold
          say "#{goal['week_start_date']} ~ #{goal['week_end_date']}"
          say ""

          updated_items = items.map do |item|
            say "目標: #{item['content']} (現在: #{item['progress']}%)"

            # 内容の変更
            content_input = ask("内容変更 [Enterでスキップ]:")
            content = if content_input.nil? || content_input.strip.empty?
                        nil
                      else
                        content_input.strip
                      end

            # 進捗率の更新
            progress_input = ask("進捗率 [#{item['progress']}]:")
            progress = if progress_input.nil? || progress_input.strip.empty?
                         item["progress"]
                       else
                         [[progress_input.to_i, 0].max, 100].min
                       end

            updated = { id: item["id"], progress: progress }
            updated[:content] = content if content
            say ""
            updated
          end

          result = client.update_weekly_goal(goal["id"], items: updated_items)
          updated_goal = result["weekly_goal"]

          if options[:json]
            say result.to_json
          else
            say ""
            say "目標を更新しました", :green
            print_goal(updated_goal)
          end
        rescue Client::ApiError => e
          CLI.error_output_from(self, e.body["error"] || "目標の更新に失敗しました")
          exit 2
        end
      end

      no_commands do
        def print_goal(goal)
          say ""
          say "期間: #{goal['week_start_date']} ~ #{goal['week_end_date']}"
          say "達成率: #{goal['completion_rate']}%"
          say "目標:"
          goal["items"].each_with_index do |item, i|
            bar = "=" * (item["progress"] / 5) + "-" * (20 - item["progress"] / 5)
            say "  #{i + 1}. #{item['content']} [#{bar}] #{item['progress']}%"
          end
        end
      end
    }

    desc "student SUBCOMMAND", "【講師】受講生の管理"
    subcommand "student", Class.new(Thor) { @_thor_name = "pdca student"

      desc "list", "受講生一覧を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :status, type: :string, desc: "ステータスでフィルタ (active/inactive)"
      option :team_id, type: :numeric, desc: "チームIDでフィルタ"
      def list
        client = CLI.require_auth_from(self)

        begin
          result = client.list_students(status: options[:status], team_id: options[:team_id])
          students = result["students"]

          if options[:json]
            say result.to_json
          elsif students.empty?
            say "受講生が見つかりません。", :yellow
          else
            say "受講生一覧 (#{result['total']}名)", :bold
            say ""
            students.each do |s|
              teams = (s["teams"] || []).join(", ")
              latest = s["latest_report_date"] ? Date.parse(s["latest_report_date"]).iso8601 : "未報告"
              say "  #{s['id']}  #{s['name']}  [#{teams}]  最終報告: #{latest}"
            end
          end
        rescue Client::ApiError => e
          if e.status == 403
            CLI.error_output_from(self, "この操作は講師のみ実行可能です")
          else
            CLI.error_output_from(self, e.body["error"] || "受講生一覧の取得に失敗しました")
          end
          exit 1
        end
      end

      desc "show", "受講生の詳細情報を表示"
      option :json, type: :boolean, default: false, desc: "JSON形式で出力"
      option :id, type: :numeric, required: true, desc: "受講生ID"
      def show
        client = CLI.require_auth_from(self)

        begin
          result = client.show_student(options[:id])
          student = result["student"]

          if options[:json]
            say result.to_json
          else
            say "受講生詳細", :bold
            say ""
            say "  名前:     #{student['name']}"
            say "  メール:   #{student['email']}"
            say "  状態:     #{student['status']}"
            say "  チーム:   #{(student['teams'] || []).join(', ')}"
            latest = student['latest_report_date'] ? Date.parse(student['latest_report_date']).iso8601 : "未報告"
            say "  最終報告: #{latest}"
            say ""
            if student["courses"] && !student["courses"].empty?
              say "  コース:"
              student["courses"].each do |c|
                say "    - #{c['name']} (#{c['status']})"
              end
            end
          end
        rescue Client::ApiError => e
          if e.status == 403
            CLI.error_output_from(self, "この操作は講師のみ実行可能です")
          elsif e.status == 404
            CLI.error_output_from(self, "受講生が見つかりません")
          else
            CLI.error_output_from(self, e.body["error"] || "受講生情報の取得に失敗しました")
          end
          exit 1
        end
      end
    }

    no_commands do
      def require_auth!
        config = Config.new
        unless config.configured?
          error_output("API URLが設定されていません。`pdca login` を実行してください。")
          exit 1
        end
        unless config.logged_in?
          error_output("ログインが必要です。`pdca login` を実行してください。")
          exit 1
        end
        Client.new(api_url: config.api_url, token: config.token)
      end

      def error_output(message)
        if options[:json]
          say({ error: message }.to_json)
        else
          say "エラー: #{message}", :red
        end
      end
    end

    # サブコマンドからも使えるようにクラスメソッドとして提供
    def self.require_auth_from(context)
      config = Config.new
      unless config.configured?
        error_output_from(context, "API URLが設定されていません。`pdca login` を実行してください。")
        exit 1
      end
      unless config.logged_in?
        error_output_from(context, "ログインが必要です。`pdca login` を実行してください。")
        exit 1
      end
      Client.new(api_url: config.api_url, token: config.token)
    end

    def self.error_output_from(context, message)
      if context.options[:json]
        context.say({ error: message }.to_json)
      else
        context.say "エラー: #{message}", :red
      end
    end
  end
end
