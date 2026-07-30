# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'

module ClaudeChats
  class TerminalTest < TestCase
    # Stands in for IO.console: hands out queued bytes and nothing more.
    class FakeConsole
      attr_reader :cooked_calls

      def initialize(bytes: '', size: [24, 80], tty: true)
        @bytes        = bytes.chars
        @size         = size
        @tty          = tty
        @cooked_calls = 0
      end

      def tty?
        @tty
      end

      def winsize
        raise 'no size available' if @size.nil?

        @size
      end

      def getch
        @bytes.shift
      end

      # Raising EOFError is how a real console reports "nothing buffered".
      def read_nonblock(_count)
        raise EOFError if @bytes.empty?

        @bytes.shift
      end

      def cooked
        @cooked_calls += 1
        yield
      end

      def cooked!
        @cooked_calls += 1
      end

      def remaining
        @bytes.join
      end
    end

    def test_plain_keys_pass_through
      terminal = build(bytes: 'dq')

      assert_equal 'd', terminal.read_key
      assert_equal 'q', terminal.read_key
    end

    def test_named_keys
      assert_equal 'enter', build(bytes: "\r").read_key
      assert_equal 'enter', build(bytes: "\n").read_key
      assert_equal 'ctrl_c', build(bytes: 3.chr).read_key
      assert_equal 'q', build(bytes: 4.chr).read_key, 'Ctrl-D quits like a shell'
    end

    def test_escape_sequences
      assert_equal 'up', build(bytes: "\e[A").read_key
      assert_equal 'down', build(bytes: "\e[B").read_key
      assert_equal 'up', build(bytes: "\eOA").read_key, 'application cursor mode'
      assert_equal 'pgup', build(bytes: "\e[5~").read_key
      assert_equal 'pgdn', build(bytes: "\e[6~").read_key
    end

    def test_lone_escape_is_escape
      assert_equal 'esc', build(bytes: "\e").read_key
    end

    def test_unknown_escape_sequence_reads_as_escape
      assert_equal 'esc', build(bytes: "\e[Z").read_key
    end

    # Keystrokes can arrive in one chunk. Consuming a fixed number of bytes after
    # an Escape would drop whatever followed the arrow key.
    def test_a_key_following_an_arrow_key_is_not_swallowed
      console  = FakeConsole.new(bytes: "\e[B/")
      terminal = Terminal.new(console: console, output: StringIO.new, error: StringIO.new)

      assert_equal 'down', terminal.read_key
      assert_equal '/', terminal.read_key
    end

    def test_no_more_input_reads_as_quit
      assert_equal 'q', build(bytes: '').read_key
    end

    def test_size_comes_from_the_console
      terminal = build(bytes: '', size: [40, 120])

      assert_equal 40, terminal.height
      assert_equal 120, terminal.width
    end

    def test_size_falls_back_when_the_console_cannot_answer
      terminal = build(bytes: '', size: nil)

      assert_equal Terminal::DEFAULT_HEIGHT, terminal.height
      assert_equal Terminal::DEFAULT_WIDTH, terminal.width
    end

    def test_zero_size_falls_back
      terminal = build(bytes: '', size: [0, 0])

      assert_equal Terminal::DEFAULT_WIDTH, terminal.width
    end

    def test_write_goes_to_stdout_and_errors_go_to_stderr
      out = StringIO.new
      err = StringIO.new
      terminal = Terminal.new(console: FakeConsole.new, output: out, error: err)

      terminal.write('hello')
      terminal.write_error('trouble')

      assert_equal 'hello', out.string
      assert_equal 'trouble', err.string
    end

    def test_read_line_uses_cooked_mode_and_strips_the_newline
      console  = FakeConsole.new
      input    = StringIO.new("some filter\n")
      terminal = Terminal.new(console: console, output: StringIO.new, error: StringIO.new, input: input)

      assert_equal 'some filter', terminal.read_line
      assert_equal 1, console.cooked_calls, 'echo has to be on while typing'
    end

    def test_alt_screen_and_restore_emit_matching_sequences
      out      = StringIO.new
      terminal = Terminal.new(console: FakeConsole.new, output: out, error: StringIO.new)

      terminal.alt_screen
      terminal.restore

      assert_includes out.string, Ansi::ALT_SCREEN_ON
      assert_includes out.string, Ansi::ALT_SCREEN_OFF
      assert_includes out.string, Ansi::HIDE_CURSOR
      assert_includes out.string, Ansi::SHOW_CURSOR
    end

    def test_not_a_tty_when_there_is_no_console
      terminal = Terminal.new(console: nil, output: StringIO.new, error: StringIO.new)

      refute_predicate terminal, :tty?
      assert_equal Terminal::DEFAULT_WIDTH, terminal.width
    end

    private

    def build(bytes:, size: [24, 80])
      Terminal.new(console: FakeConsole.new(bytes: bytes, size: size),
                   output: StringIO.new, error: StringIO.new)
    end
  end
end
