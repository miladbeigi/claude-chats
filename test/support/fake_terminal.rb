# frozen_string_literal: true

module ClaudeChats
  # Scripted stand-in for Terminal.
  #
  # Keys come from a queue and output is captured, so the UI can be driven
  # deterministically without a pseudo-terminal or a single sleep. Running out of
  # keys reads as 'q', which ends the loop the same way a real user would.
  class FakeTerminal
    ANY_ESCAPE = /\e\[[0-9;?]*[A-Za-z]/

    attr_reader :output, :errors, :alt_screens, :restores, :width, :height
    attr_accessor :keys, :answers

    def initialize(keys: [], answers: [], width: 100, height: 20, tty: true)
      @keys        = keys
      @answers     = answers
      @width       = width
      @height      = height
      @tty         = tty
      @output      = +''
      @errors      = +''
      @alt_screens = 0
      @restores    = 0
    end

    def tty?
      @tty
    end

    def write(text)
      @output << text.to_s
    end

    def write_error(text)
      @errors << text.to_s
    end

    def alt_screen
      @alt_screens += 1
    end

    def restore
      @restores += 1
    end

    def read_key
      @keys.shift || 'q'
    end

    def read_line
      @answers.shift.to_s
    end

    # Everything the user would have seen, one entry per screen repaint.
    def frames
      @output.split(Ansi::CLEAR_SCREEN)
    end

    def last_frame
      frames.last.to_s
    end

    # Lines of the final screen with every escape sequence removed.
    def last_frame_lines
      plain(last_frame).split("\r\n")
    end

    def plain(text)
      text.to_s.gsub(ANY_ESCAPE, '')
    end

    def plain_output
      plain(@output)
    end
  end
end
