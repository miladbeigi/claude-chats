# frozen_string_literal: true

module ClaudeChats
  # Adapter over the real terminal.
  #
  # Browser talks only to this interface, which keeps every escape sequence and
  # raw-mode read in one place and lets the tests drive the UI with a scripted
  # fake instead of a pseudo-terminal.
  class Terminal
    KEYS = {
      "\r" => 'enter',
      "\n" => 'enter',
      "\u0003" => 'ctrl_c', # Ctrl-C
      "\u0004" => 'q',      # Ctrl-D quits, as in a shell
      "\e[A" => 'up',
      "\e[B" => 'down',
      "\eOA" => 'up',
      "\eOB" => 'down',
      "\e[5~" => 'pgup',
      "\e[6~" => 'pgdn',
      "\e" => 'esc'
    }.freeze

    DEFAULT_HEIGHT = 24
    DEFAULT_WIDTH  = 80
    ESCAPE_BYTES   = 3

    def initialize(console: IO.console, output: $stdout, error: $stderr, input: $stdin)
      @console = console
      @output  = output
      @error   = error
      @input   = input
    end

    def tty?
      !@console.nil? && @console.tty?
    end

    def height
      winsize.first
    end

    def width
      winsize.last
    end

    def write(text)
      @output.print(text)
      @output.flush
    end

    def write_error(text)
      @error.print(text)
    end

    def alt_screen
      write("#{Ansi::ALT_SCREEN_ON}#{Ansi::HIDE_CURSOR}")
    end

    # Undo everything alt_screen did, and hand the terminal back in a state a
    # shell can use — this runs even when the UI is torn down by an exception.
    def restore
      write("#{Ansi::SHOW_CURSOR}#{Ansi::ALT_SCREEN_OFF}")
      @console.cooked! if tty?
    end

    def read_key
      char = @console&.getch
      return 'q' if char.nil?
      return read_escape if char == "\e"

      KEYS.fetch(char, char)
    end

    # Line of input for the filter and confirmation prompts. The cursor is shown
    # while typing and echo comes back on, otherwise nothing appears.
    def read_line
      write(Ansi::SHOW_CURSOR)
      line = @console ? @console.cooked { @input.gets } : @input.gets
      write(Ansi::HIDE_CURSOR)
      line.to_s.chomp
    end

    private

    # An arrow or page key arrives as several bytes. Only what is already
    # buffered gets read, so a lone Escape does not block waiting for a
    # sequence, and reading stops the moment the sequence is complete —
    # otherwise a key pressed straight after an arrow key is swallowed with it.
    def read_escape
      sequence = +"\e"
      ESCAPE_BYTES.times do
        byte = next_byte
        break if byte.nil?

        sequence << byte
        known = KEYS[sequence]
        return known if known
        break unless prefix_of_a_key?(sequence)
      end

      KEYS.fetch(sequence, 'esc')
    end

    # IOError covers EOFError; SystemCallError covers the Errno::EAGAIN family
    # that carries IO::WaitReadable. Either way: nothing more is buffered.
    def next_byte
      @console.read_nonblock(1)
    rescue IOError, SystemCallError
      nil
    end

    def prefix_of_a_key?(sequence)
      KEYS.each_key.any? { |key| key.length > sequence.length && key.start_with?(sequence) }
    end

    def winsize
      size = @console&.winsize
      return size if size.is_a?(Array) && size.size == 2 && size.all?(&:positive?)

      [DEFAULT_HEIGHT, DEFAULT_WIDTH]
    rescue StandardError
      [DEFAULT_HEIGHT, DEFAULT_WIDTH]
    end
  end
end
