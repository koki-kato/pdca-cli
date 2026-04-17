require "net/http"
require "uri"
require "json"
require "openssl"

module PdcaCli
  class Client
    class ApiError < StandardError
      attr_reader :status, :body

      def initialize(status, body)
        @status = status
        @body = body
        super("API Error (#{status}): #{body}")
      end
    end

    def initialize(api_url:, token: nil)
      url = api_url.strip.chomp("/")
      url = "https://#{url}" unless url.match?(%r{\Ahttps?://})
      @api_url = url
      @token = token
    end

    # 認証
    def login(email:, password:)
      post("/api/v1/auth/login", { email: email, password: password }, auth: false)
    end

    def me
      get("/api/v1/auth/me")
    end

    # 報告
    def create_report(params)
      post("/api/v1/reports", { report: params })
    end

    def today_report
      get("/api/v1/reports/today")
    end

    def list_reports(month: nil, limit: nil)
      query = {}
      query[:month] = month if month
      query[:limit] = limit if limit
      get("/api/v1/reports", query)
    end

    def show_report(id)
      get("/api/v1/reports/#{id}")
    end

    def report_by_date(date)
      get("/api/v1/reports/by_date", { date: date })
    end

    def update_report(id, params)
      patch("/api/v1/reports/#{id}", { report: params })
    end

    # 週次目標
    def current_weekly_goal
      get("/api/v1/weekly_goals/current")
    end

    def list_weekly_goals(limit: nil)
      query = {}
      query[:limit] = limit if limit
      get("/api/v1/weekly_goals", query)
    end

    def create_weekly_goal(items:, week_start: nil, force: false)
      body = { items: items }
      body[:week_start] = week_start if week_start
      body[:force] = true if force
      post("/api/v1/weekly_goals", body)
    end

    def update_weekly_goal(id, items:)
      patch("/api/v1/weekly_goals/#{id}", { items: items })
    end

    # 学習計画
    def get_plan
      get("/api/v1/plan")
    end

    def setup_plan(course_name:, categories:)
      post("/api/v1/plan/setup", { course_name: course_name, categories: categories })
    end

    def add_plan_category(name:, estimated_hours: 0)
      post("/api/v1/plan/categories", { name: name, estimated_hours: estimated_hours })
    end

    # 講師向け: 受講生
    def list_students(status: nil, team: nil)
      query = {}
      query[:status] = status if status
      query[:team_name] = team.strip if team.to_s.strip.presence
      get("/api/v1/instructor/students", query)
    end

    def show_student(id)
      get("/api/v1/instructor/students/#{id}")
    end

    # 講師向け: 進捗確認
    def list_progress(team: nil)
      query = {}
      query[:team_name] = team.strip if team.to_s.strip.presence
      get("/api/v1/instructor/progress", query)
    end

    def show_progress(id)
      get("/api/v1/instructor/progress/#{id}")
    end

    # 講師向け: ダッシュボード
    def dashboard_daily(date: nil, team: nil, status: nil)
      query = {}
      query[:date] = date if date
      query[:team_name] = team.strip if team.to_s.strip.presence
      query[:status] = status if status
      get("/api/v1/instructor/dashboard/daily", query)
    end

    def dashboard_weekly(week_offset: nil, team: nil)
      query = {}
      query[:week_offset] = week_offset if week_offset
      query[:team_name] = team.strip if team.to_s.strip.presence
      get("/api/v1/instructor/dashboard/weekly", query)
    end

    # コメント（講師・受講生共通）
    def list_comments(report_id:)
      get("/api/v1/comments", { report_id: report_id })
    end

    def create_comment(report_id:, content:)
      post("/api/v1/comments", { report_id: report_id, content: content })
    end

    def delete_comment(id)
      delete("/api/v1/comments/#{id}")
    end

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

    private

    def get(path, query = {})
      uri = build_uri(path, query)
      request = Net::HTTP::Get.new(uri.request_uri)
      execute(uri, request)
    end

    def post(path, body, auth: true)
      uri = build_uri(path)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = body.to_json
      request["Content-Type"] = "application/json"
      execute(uri, request, auth: auth)
    end

    def patch(path, body)
      uri = build_uri(path)
      request = Net::HTTP::Patch.new(uri.request_uri)
      request.body = body.to_json
      request["Content-Type"] = "application/json"
      execute(uri, request)
    end

    def delete(path)
      uri = build_uri(path)
      request = Net::HTTP::Delete.new(uri.request_uri)
      execute(uri, request)
    end

    def build_uri(path, query = {})
      uri = URI.parse("#{@api_url}#{path}")
      uri.query = URI.encode_www_form(query) unless query.empty?
      uri
    end

    def execute(uri, request, auth: true)
      request["Authorization"] = "Bearer #{@token}" if auth && @token
      request["Accept"] = "application/json"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      if http.use_ssl?
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        # macOS環境でCRL(証明書失効リスト)取得に失敗するケースに対応
        # CRL関連エラーのみスキップし、その他のSSL検証は通常通り行う
        http.verify_callback = proc do |preverify_ok, store_ctx|
          unless preverify_ok
            crl_errors = [
              OpenSSL::X509::V_ERR_UNABLE_TO_GET_CRL,  # CRL取得不可
              OpenSSL::X509::V_ERR_CRL_NOT_YET_VALID,   # CRL未発効
            ]
            next true if crl_errors.include?(store_ctx.error)
          end
          preverify_ok
        end
      end
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(request)
      body = (response.body && !response.body.empty?) ? JSON.parse(response.body) : {}

      case response.code.to_i
      when 200..299
        body
      else
        raise ApiError.new(response.code.to_i, body)
      end
    rescue JSON::ParserError
      raise ApiError.new(response.code.to_i, { "error" => response.body })
    rescue OpenSSL::SSL::SSLError => e
      raise ApiError.new(0, { "error" => "SSL接続エラー: #{e.message}" })
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout => e
      raise ApiError.new(0, { "error" => "サーバーに接続できません: #{e.message}" })
    end
  end
end
