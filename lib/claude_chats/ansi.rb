# frozen_string_literal: true

module ClaudeChats
  # The handful of escape sequences the UI needs, plus a way to measure a string
  # once its colour codes are discounted.
  module Ansi
    RESET   = "\e[0m"
    BOLD    = "\e[1m"
    DIM     = "\e[2m"
    REVERSE = "\e[7m"
    RED     = "\e[31m"
    GREEN   = "\e[32m"
    YELLOW  = "\e[33m"
    MAGENTA = "\e[35m"
    CYAN    = "\e[36m"

    CLEAR_SCREEN  = "\e[H\e[2J"
    CLEAR_LINE    = "\e[K"
    ALT_SCREEN_ON = "\e[?1049h"
    ALT_SCREEN_OFF = "\e[?1049l"
    HIDE_CURSOR   = "\e[?25l"
    SHOW_CURSOR   = "\e[?25h"

    # Colour codes only. Cursor movement and erase codes are deliberately left
    # alone so callers can still reason about them.
    COLOUR = /\e\[[0-9;]*m/

    def self.strip(str)
      str.to_s.gsub(COLOUR, '')
    end

    # Printable length of a string once colour codes are removed.
    def self.length(str)
      strip(str).length
    end

    # Cuts a rendered line that is already carrying colour codes. Appending a
    # reset keeps a severed sequence from colouring the rest of the screen.
    def self.truncate(line, max)
      return line if length(line) <= max

      "#{line[0, max]}#{RESET}"
    end

    # Cuts plain text to fit, marking that something was left out. Use #truncate
    # instead for a line that already carries colour codes.
    def self.clip(text, max)
      text = text.to_s
      return '' if max <= 0
      return text if text.length <= max

      max == 1 ? '…' : "#{text[0, max - 1]}…"
    end

    def self.move_to(row, column = 1)
      "\e[#{row};#{column}H"
    end
  end
end
