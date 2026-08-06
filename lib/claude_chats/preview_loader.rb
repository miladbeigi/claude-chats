# frozen_string_literal: true

module ClaudeChats
  # Reads the tail of one transcript: the last few turns that actually said
  # something, for the row under the cursor.
  #
  # Deliberately not a second SessionLoader. That one reads whole files to count
  # messages, at startup, once. This one runs on every cursor move, so it seeks
  # to the end of the file and reads a bounded window instead — a chat with a
  # megabyte of tool output costs the same as a short one.
  class PreviewLoader
    Turn = Struct.new(:role, :text)

    TURNS      = 3
    WINDOW     = 32 * 1024
    MAX_WINDOW = 1024 * 1024
    GROWTH     = 4

    UNAVAILABLE = :unavailable

    def initialize(paths: Paths.new, turns: TURNS, window: WINDOW, max_window: MAX_WINDOW)
      @paths      = paths
      @turns      = turns
      @window     = window
      @max_window = max_window
      @cache      = {}
    end

    # An array of Turn — empty when nothing in the file reads as conversation —
    # or UNAVAILABLE when the file cannot be read at all.
    def turns_for(session)
      @cache.fetch(session.id) { @cache[session.id] = load(session.path) }
    end

    def forget(id)
      @cache.delete(id)
    end

    private

    # Widens the window and re-reads when the tail turned up too little. Most of
    # an agentic chat is tool calls, so the last 32K can hold no prose at all.
    # Re-reading is cheaper than it looks: four attempts cap out under 1.7 MB.
    def load(path)
      size   = File.size(path)
      window = @window

      loop do
        found = scan_tail(path, size, window)
        return found if found.size >= @turns || window >= size || window >= @max_window

        window *= GROWTH
      end
    rescue SystemCallError
      UNAVAILABLE
    end

    def scan_tail(path, size, window)
      offset = [size - window, 0].max
      turns  = []

      File.open(path, 'rb') do |file|
        file.seek(offset)
        # Seeking lands mid-line, and half a JSON record is not a record.
        file.readline unless offset.zero?

        file.each_line do |line|
          turn = turn_from(line)
          next unless turn

          turns << turn
          turns.shift if turns.size > @turns
        end
      end

      turns
    rescue EOFError
      turns # the file shrank between sizing it and reading it
    end

    # Mirrors SessionLoader's idea of a message: no sidechains, no wrapper
    # records, and nothing whose content carries no text — which is what drops
    # tool calls, tool results and thinking blocks.
    def turn_from(line)
      # Read as bytes so the seek offsets mean something; the encoding has to be
      # put back by hand, and a window boundary can leave invalid bytes behind.
      record = Records.parse_line(line.force_encoding(Encoding::UTF_8).scrub)
      return unless record && %w[user assistant].include?(record['type'])
      return if record['isSidechain']

      text = Records.normalise(Records.sanitise(Records.extract_text(record.dig('message', 'content'))))
      return if text.empty? || text.match?(Records::NOISE)

      command = text.match(Records::COMMAND_NAME)
      Turn.new(record['type'] == 'user' ? :you : :claude, command ? command[1] : text)
    end
  end
end
