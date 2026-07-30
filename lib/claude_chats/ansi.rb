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

    def self.move_to(row, column = 1)
      "\e[#{row};#{column}H"
    end
  end
end
