# frozen_string_literal: true

require_relative 'lib/claude_chats/version'

Gem::Specification.new do |spec|
  spec.name        = 'claude-chats'
  spec.version     = ClaudeChats::VERSION
  spec.authors     = ['Milad Beigi']
  spec.email       = ['milad.be@gmail.com']

  spec.summary     = 'Browse, resume and delete Claude Code chats from your terminal'
  spec.description = <<~DESCRIPTION
    A small terminal UI over the chat transcripts Claude Code keeps on disk.
    List them newest first, filter by project or text, open one with `claude
    --resume`, or mark several and delete them behind a confirmation prompt.
    No dependencies beyond the Ruby standard library.
  DESCRIPTION

  spec.homepage = 'https://github.com/miladbeigi/claude-chats'
  spec.license  = 'MIT'
  spec.required_ruby_version = '>= 3.1'

  spec.metadata = {
    'homepage_uri'          => spec.homepage,
    'source_code_uri'       => "#{spec.homepage}/tree/v#{spec.version}",
    'changelog_uri'         => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri'       => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files       = Dir['lib/**/*.rb'] + Dir['exe/*'] + %w[README.md CHANGELOG.md LICENSE]
  spec.bindir      = 'exe'
  spec.executables = ['claude-chats']
  spec.require_paths = ['lib']
end
