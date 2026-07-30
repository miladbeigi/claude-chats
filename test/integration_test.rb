# frozen_string_literal: true

require_relative 'test_helper'
require 'English'
require 'rbconfig'

begin
  require 'pty'
rescue LoadError
  # Checked in setup; the rest of the suite still runs everywhere else.
end

module ClaudeChats
  # Drives the real executable through a pseudo-terminal.
  #
  # Everything else fakes the terminal, so this is the one test that exercises
  # IO.console for real: raw-mode key reads, cooked-mode prompts, the alternate
  # screen and winsize. It deliberately cancels at the confirmation prompt — the
  # destructive paths are covered against fixtures in browser_test.rb.
  class IntegrationTest < TestCase
    EXE     = File.expand_path('../exe/claude-chats', __dir__)
    TIMEOUT = 15
    TICK    = 0.05

    # Keystrokes and screen assertions for a child process. Output is collected
    # by a pump thread, so the child never blocks writing into a full buffer
    # while the test is busy asserting.
    class Driver
      def initialize(writer, buffer, timeout:, tick:)
        @writer  = writer
        @buffer  = buffer
        @timeout = timeout
        @tick    = tick
      end

      def press(keys)
        @writer.write(keys)
      end

      def expect(pattern)
        deadline = Time.now + @timeout
        until @buffer.match?(pattern)
          raise "timed out waiting for #{pattern.inspect}, screen was:\n#{screen}" if Time.now > deadline

          sleep @tick
        end
        true
      end

      def screen
        @buffer.gsub(/\e\[[0-9;?]*[A-Za-z]/, '').split("\r\n").reject(&:empty?).last(12).join("\n")
      end
    end

    def setup
      super
      skip 'PTY is unavailable on this platform' unless defined?(PTY)
    end

    def test_marking_then_cancelling_leaves_every_chat_in_place
      builder.chat(id: 'aaaa', text: 'first real chat', mtime: Time.now - 30)
      builder.chat(id: 'bbbb', text: 'second real chat', mtime: Time.now - 60)

      status = drive do |term|
        term.expect(/Claude Code chats/)
        term.expect(/first real chat/)

        term.press('d')
        term.expect(/1 marked/)
        term.press('d')
        term.expect(/2 marked/)

        term.press("\r")
        term.expect(/Permanently delete 2 chats/)
        term.expect(/This cannot be undone/)

        term.press("no\r")
        term.expect(/Cancelled/)

        term.press('q')
      end

      assert_equal 0, status&.exitstatus
      assert_equal %w[aaaa bbbb], transcripts, 'cancelling must leave both chats on disk'
    end

    def test_arrow_keys_and_filtering_work_against_a_real_terminal
      builder.chat(id: 'aaaa', text: 'vault raft rollout', mtime: Time.now - 30)
      builder.chat(id: 'bbbb', text: 'pipeline debugging', mtime: Time.now - 60)

      status = drive do |term|
        term.expect(/Claude Code chats/)

        term.press("\e[B") # arrow down onto the second chat
        term.press('/')
        term.expect(/filter:/)
        term.press("vault\r")
        term.expect(%r{1/2 chats})
        term.expect(/vault raft rollout/)

        term.press('q')
      end

      assert_equal 0, status&.exitstatus
      assert_equal %w[aaaa bbbb], transcripts
    end

    def test_quitting_leaves_the_terminal_usable
      builder.chat(id: 'aaaa', text: 'a chat')
      screen = nil

      drive do |term|
        term.expect(/Claude Code chats/)
        term.press('q')
        screen = term
      end

      # Leaving the alternate screen and showing the cursor again.
      assert_match(/\e\[\?25h/, raw_output)
      assert_match(/\e\[\?1049l/, raw_output)
      refute_nil screen
    end

    def test_listing_without_a_terminal_still_works
      builder.chat(id: 'aaaa', text: 'piped output chat')
      output = IO.popen(child_env, [RbConfig.ruby, EXE, '--list'], err: %i[child out], &:read)

      assert_predicate $CHILD_STATUS, :success?
      assert_includes output, 'piped output chat'
    end

    private

    attr_reader :raw_output

    def child_env
      # A deliberately bare PATH: nothing here should need to find claude.
      { 'CLAUDE_CONFIG_DIR' => tmp, 'PATH' => '/usr/bin:/bin', 'TERM' => 'xterm-256color',
        'LINES' => '20', 'COLUMNS' => '100' }
    end

    def drive
      buffer = +''
      status = nil

      PTY.spawn(child_env, RbConfig.ruby, EXE) do |reader, writer, pid|
        resize(reader)
        pump = start_pump(reader, buffer)
        begin
          yield Driver.new(writer, buffer, timeout: TIMEOUT, tick: TICK)
        ensure
          status = reap(pid, buffer)
          pump.kill
        end
      end

      @raw_output = buffer
      status
    end

    def start_pump(reader, buffer)
      Thread.new do
        loop { buffer << reader.readpartial(4096) }
      rescue IOError, SystemCallError
        nil # the child closed the terminal by exiting
      end
    end

    def resize(reader)
      reader.winsize = [20, 100]
    rescue StandardError
      nil # not fatal: Terminal falls back to sane defaults
    end

    def reap(pid, buffer)
      deadline = Time.now + TIMEOUT
      while Time.now < deadline
        _, status = Process.waitpid2(pid, Process::WNOHANG)
        return status if status

        sleep TICK
      end

      Process.kill('KILL', pid)
      flunk "the browser did not exit, screen was:\n#{buffer[-400..] || buffer}"
    rescue Errno::ECHILD, Errno::ESRCH
      nil
    end
  end
end
