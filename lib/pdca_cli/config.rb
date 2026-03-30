require "yaml"
require "fileutils"

module PdcaCli
  class Config
    CONFIG_PATH = File.expand_path("~/.pdca.yml")

    attr_accessor :api_url, :token

    def initialize
      load_from_file if File.exist?(CONFIG_PATH)
      # 環境変数で上書き
      @api_url = ENV["PDCA_API_URL"] if ENV["PDCA_API_URL"]
      @token = ENV["PDCA_TOKEN"] if ENV["PDCA_TOKEN"]
    end

    def save!
      data = {}
      data["api_url"] = @api_url if @api_url
      data["token"] = @token if @token

      File.write(CONFIG_PATH, YAML.dump(data))
      File.chmod(0600, CONFIG_PATH)
    end

    def clear!
      File.delete(CONFIG_PATH) if File.exist?(CONFIG_PATH)
    end

    def logged_in?
      @token && !@token.empty?
    end

    def configured?
      @api_url && !@api_url.empty?
    end

    private

    def load_from_file
      data = YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: []) || {}
      @api_url = data["api_url"]
      @token = data["token"]
    rescue Psych::SyntaxError
      # 設定ファイルが壊れている場合は無視
    end
  end
end
