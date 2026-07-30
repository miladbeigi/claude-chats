# frozen_string_literal: true

require 'fileutils'
require 'io/console'
require 'json'
require 'optparse'
require 'time'

require_relative 'claude_chats/version'
require_relative 'claude_chats/ansi'
require_relative 'claude_chats/paths'
require_relative 'claude_chats/session'
require_relative 'claude_chats/session_loader'
require_relative 'claude_chats/terminal'
require_relative 'claude_chats/launcher'
require_relative 'claude_chats/browser'
require_relative 'claude_chats/cli'

# Browse and delete Claude Code chat sessions from the terminal.
module ClaudeChats
end
