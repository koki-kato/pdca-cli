module PdcaCli
  class Interactive
    def initialize(shell)
      @shell = shell
    end

    # 報告作成の対話型プロンプト
    def ask_report_params
      today = Date.today.iso8601
      @shell.say ""
      @shell.say "PDCA日次報告を作成します", :bold

      # 日付
      date = @shell.ask("報告日 [#{today}]:")
      date = today if date.nil? || date.strip.empty?

      # 学習状況
      @shell.say ""
      @shell.say "今日の学習状況は？"
      @shell.say "  1) green  - 順調、問題なし"
      @shell.say "  2) yellow - 詰まっているが対処できそう"
      @shell.say "  3) red    - 完全に止まっている"
      status_input = @shell.ask("選択 [1-3]:")
      status = case status_input&.strip
               when "1", "green" then "green"
               when "2", "yellow" then "yellow"
               when "3", "red" then "red"
               else
                 @shell.say "無効な入力です。greenとして扱います。", :yellow
                 "green"
               end

      # PDCA各項目
      @shell.say ""
      plan = @shell.ask("Plan: 今日の学習計画は？")
      do_text = @shell.ask("Do: 実際に何をしましたか？ (空欄でスキップ)")
      check = @shell.ask("Check: 振り返りは？ (空欄でスキップ)")
      action = @shell.ask("Action: 次のアクションは？ (空欄でスキップ)")

      params = {
        report_date: date,
        learning_status: status,
        learning_plan: plan
      }
      params[:learning_do] = do_text unless do_text.nil? || do_text.strip.empty?
      params[:learning_check] = check unless check.nil? || check.strip.empty?
      params[:learning_action] = action unless action.nil? || action.strip.empty?

      # 確認
      @shell.say ""
      @shell.say "--- 確認 ---"
      @shell.say "日付:   #{params[:report_date]}"
      @shell.say "状況:   #{params[:learning_status]}"
      @shell.say "Plan:   #{params[:learning_plan]}"
      @shell.say "Do:     #{params[:learning_do] || '(未入力)'}"
      @shell.say "Check:  #{params[:learning_check] || '(未入力)'}"
      @shell.say "Action: #{params[:learning_action] || '(未入力)'}"
      @shell.say ""

      unless @shell.yes?("送信しますか？ [Y/n]")
        @shell.say "キャンセルしました。", :yellow
        return nil
      end

      params
    end

    # ログインの対話型プロンプト
    def ask_login_params(current_api_url: nil)
      default_url = current_api_url || ""
      prompt = current_api_url ? "API URL [#{current_api_url}]:" : "API URL:"
      api_url = @shell.ask(prompt)
      api_url = current_api_url if (api_url.nil? || api_url.strip.empty?) && current_api_url

      email = @shell.ask("メールアドレス:")
      password = @shell.ask("パスワード:", echo: false)
      @shell.say ""

      { api_url: api_url, email: email, password: password }
    end
  end
end
