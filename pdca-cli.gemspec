require_relative "lib/pdca_cli/version"

Gem::Specification.new do |spec|
  spec.name = "pdca-cli"
  spec.version = PdcaCli::VERSION
  spec.authors = ["PDCA App"]
  spec.summary = "PDCA報告CLIツール"
  spec.description = "プログラミングスクール向けPDCA日次報告をコマンドラインから送信するツール"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir["lib/**/*.rb", "bin/*"]
  spec.bindir = "bin"
  spec.executables = ["pdca"]

  spec.add_dependency "thor", "~> 1.3"
end
