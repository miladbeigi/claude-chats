# frozen_string_literal: true

module ClaudeChats
  # The pane to the right of the list: what the highlighted chat last said.
  #
  # Exists so Browser does not have to know about word wrapping, and returns a
  # fixed number of lines so the pane cannot change the height of the screen.
  class Preview
    DIVIDER = ' │ '
    CAPTION_ROWS = 2 # caption + blank

    LABELS = { you: 'you', claude: 'claude' }.freeze
    # A colour each, so who said what is legible without reading the label. Red
    # and green are spoken for elsewhere in the list — marked, and live — and
    # yellow is the status line, which leaves these two.
    COLOURS = { you: Ansi::CYAN, claude: Ansi::MAGENTA }.freeze
    GUTTER = 8 # LABELS' longest, right-aligned, plus two spaces
    PER_TURN_LINES = 4

    UNAVAILABLE = '(transcript unavailable)'
    NO_TEXT     = '(no message text)'
    EMPTY       = '(empty chat)'

    def initialize(session, turns, now:)
      @session = session
      @turns   = turns
      @now     = now
    end

    # Puts the pane beside lines that have already been rendered, padding them
    # out so the divider forms a straight column.
    def beside(left, list_width:, width:)
      pane = lines(width: width - list_width - DIVIDER.length, rows: left.size)

      left.zip(pane).map do |line, right|
        cut     = Ansi.truncate(line, list_width)
        padding = ' ' * [list_width - Ansi.length(cut), 0].max
        "#{cut}#{padding}#{DIVIDER}#{right}"
      end
    end

    # Exactly `rows` lines, none of them wider than `width`.
    def lines(width:, rows:)
      body = [caption(width), '', *turn_lines(width)]
      # The newest turn is the one worth keeping, so overflow is dropped from the
      # top rather than the bottom.
      body = body.first(CAPTION_ROWS) + body.drop(CAPTION_ROWS).last(rows - CAPTION_ROWS) if body.size > rows
      body.first(rows) + Array.new([rows - body.size, 0].max, '')
    end

    private

    def caption(width)
      return '' unless @session

      text = "#{@session.project} · #{@session.age(@now)} · #{@session.messages} msg"
      dim(text, width)
    end

    def turn_lines(width)
      return [dim(state, width)] if state

      @turns.flat_map { |turn| render(turn, width) }
    end

    # Nothing to say about no row at all — the filter matched nothing.
    def state
      return nil if @session.nil?
      return UNAVAILABLE if @turns == PreviewLoader::UNAVAILABLE
      return nil unless @turns.empty?

      @session.messages.zero? ? EMPTY : NO_TEXT
    end

    # Label in a fixed left gutter, text wrapped in what is left. A ragged
    # left edge is harder to read than a narrower column.
    def render(turn, width)
      room    = [width - GUTTER, 1].max
      wrapped = wrap(turn.text, room)
      label   = LABELS.fetch(turn.role, '?').rjust(GUTTER - 2)
      colour  = COLOURS.fetch(turn.role, Ansi::DIM)
      kept    = wrapped.first(PER_TURN_LINES)
      kept[-1] = Ansi.clip("#{kept.last} …", room) if wrapped.size > kept.size

      # The whole turn is coloured, continuation lines included, so a message
      # reads as one block; the label stays picked out by the gutter it sits in.
      kept.each_with_index.map do |line, index|
        gutter = index.zero? ? "#{label}  " : ' ' * GUTTER
        "#{colour}#{gutter}#{line}#{Ansi::RESET}"
      end
    end

    def wrap(text, room)
      lines = []
      words(text, room).each do |word|
        if lines.empty? || lines.last.length + 1 + word.length > room
          lines << +word.dup
        else
          lines.last << ' ' << word
        end
      end
      lines.empty? ? [''] : lines
    end

    # A path or a stack trace has no spaces to break on, so cut it into chunks
    # that do fit rather than letting the line overflow.
    def words(text, room)
      text.split(' ').flat_map { |word| word.length <= room ? word : word.scan(/.{1,#{room}}/) }
    end

    def dim(text, width)
      "#{Ansi::DIM}#{Ansi.clip(text, width)}#{Ansi::RESET}"
    end
  end
end
