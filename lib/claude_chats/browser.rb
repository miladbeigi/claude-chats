# frozen_string_literal: true

module ClaudeChats
  # The full-screen list. Marks are collected first and acted on once, so no
  # single keystroke can delete anything.
  #
  # #run returns the Session the user asked to resume, or nil if they just quit.
  # Launching is left to the caller: this class never replaces the process.
  class Browser
    HEADER_ROWS = 2 # title + blank
    FOOTER_ROWS = 3 # blank + help + status/prompt line
    MIN_ROWS    = 3
    MAX_WIDTH   = 200
    MIN_WIDTH   = 40

    HELP = 'j/k move · o open · p preview · d mark · D all · u none · / filter · Enter delete marked · q quit'
    CONFIRM_WORD = 'yes'

    # Every key the list responds to. Quitting is handled by the loop itself.
    ACTIONS = {
      'up' => :move_up,      'k' => :move_up,
      'down' => :move_down,  'j' => :move_down,
      'pgup' => :page_up,    'pgdn' => :page_down,
      'g' => :go_first,      'G' => :go_last,
      'd' => :toggle_mark,   ' ' => :toggle_mark,
      'D' => :mark_all,      'u' => :unmark_all,
      'o' => :stage_resume,  '/' => :prompt_filter,
      'p' => :toggle_preview,
      'esc' => :clear_state, 'enter' => :confirm_and_delete
    }.freeze

    # Columns taken by the fixed-width metadata block plus the mark and padding.
    META_WIDTH  = 6
    TITLE_FLOOR = 10
    PROJECT_WIDTH = 18
    # With the pane open the columns have to come from somewhere: the project is
    # narrower and the size goes, since the pane makes both less interesting.
    COMPACT_PROJECT = 12

    PANE_SHARE = 3
    PANE_MIN   = 28
    PANE_MAX   = 60
    # Below this the pane would leave the list too narrow to read a title in, so
    # the rows get the whole screen back instead.
    PANE_FLOOR = 80

    def initialize(sessions, terminal:, paths: Paths.new, launcher: nil, trash: false,
                   clock: Time, previews: nil)
      @sessions = sessions
      @terminal = terminal
      @paths    = paths
      @launcher = launcher || Launcher.new(paths: paths)
      @trash    = trash
      @clock    = clock
      @previews = previews || PreviewLoader.new(paths: paths)
      # Off until asked for: the list is what you came for, and the pane costs it
      # a third of its columns.
      @preview  = false
      @marked   = {}
      @cursor   = 0
      @offset   = 0
      @filter   = ''
      @status   = nil
      @deleted  = 0
      @resume   = nil
    end

    def run
      return report_empty if @sessions.empty?
      return fallback_list unless @terminal.tty?

      @terminal.alt_screen
      interact
      @resume
    ensure
      @terminal.restore
      report
    end

    private

    def interact
      loop do
        draw
        key = @terminal.read_key
        break if %w[q ctrl_c].include?(key)

        handle(key)
        break if @resume
      end
    end

    def report_empty
      @terminal.write("No Claude Code chats found.\n")
      nil
    end

    def fallback_list
      @sessions.each { |session| @terminal.write("#{session.to_line(now)}\n") }
      @terminal.write_error("\nNot a TTY — listing only. Run from an interactive terminal to delete.\n")
      nil
    end

    def now
      @clock.now
    end

    def visible
      @visible ||= @sessions.select { |session| session.matches?(@filter) }
    end

    def invalidate
      @visible = nil
      @cursor  = 0
      @offset  = 0
    end

    def rows
      [@terminal.height - HEADER_ROWS - FOOTER_ROWS, MIN_ROWS].max
    end

    # One column short of the real width, so a full-width row never soft-wraps
    # onto the next line and pushes the layout down.
    def width
      (@terminal.width - 1).clamp(MIN_WIDTH, MAX_WIDTH)
    end

    def preview?
      @preview && width >= PANE_FLOOR
    end

    def list_width
      width - (width / PANE_SHARE).clamp(PANE_MIN, PANE_MAX) - Preview::DIVIDER.length
    end

    # The columns a row has to render into, pane or no pane.
    def row_width
      preview? ? list_width : width
    end

    def current
      visible[@cursor]
    end

    def handle(key)
      @status = nil
      action = ACTIONS[key]
      send(action) if action
    end

    def move_up
      move(-1)
    end

    def move_down
      move(1)
    end

    def page_up
      move(-rows)
    end

    def page_down
      move(rows)
    end

    def go_first
      move(-@sessions.size)
    end

    def go_last
      move(@sessions.size)
    end

    def mark_all
      visible.each { |session| @marked[session.id] = session }
    end

    def unmark_all
      @marked.clear
    end

    # Escape deliberately does not reach this: it backs out of the filter and the
    # marks, and losing the pane on the way to clearing a filter is a surprise.
    def toggle_preview
      @preview = !@preview
    end

    def toggle_mark
      session = current or return

      if @marked.key?(session.id)
        @marked.delete(session.id)
      else
        @marked[session.id] = session
      end
      move(1)
    end

    # Escape backs out one layer at a time: the filter first, then the marks.
    def clear_state
      if @filter.empty?
        @marked.clear
      else
        @filter = ''
        invalidate
      end
    end

    def move(delta)
      return if visible.empty?

      @cursor = visible.size - 1 if @cursor >= visible.size
      @cursor = (@cursor + delta).clamp(0, visible.size - 1)
      @offset = @cursor if @cursor < @offset
      @offset = @cursor - rows + 1 if @cursor >= @offset + rows
      @offset = @offset.clamp(0, [visible.size - rows, 0].max)
    end

    # The pane shares the rows the list occupies, so it can never change how tall
    # the screen is; the help and status lines keep the full width.
    def draw
      band  = [header, '', *list_rows]
      band  = pane.beside(band, list_width: list_width, width: width) if preview?
      lines = [*band, '', "#{Ansi::DIM}#{HELP}#{Ansi::RESET}"]
      lines << "#{Ansi::YELLOW}#{@status}#{Ansi::RESET}" if @status

      body = lines.map { |line| "#{Ansi.truncate(line, width)}#{Ansi::CLEAR_LINE}" }.join("\r\n")
      @terminal.write("#{Ansi::CLEAR_SCREEN}#{body}")
    end

    def list_rows
      slice = visible[@offset, rows] || []
      drawn = slice.each_with_index.map { |session, i| row(session, @offset + i == @cursor) }
      drawn + Array.new(rows - slice.size, '')
    end

    # Reading the transcript is left until here, so it only ever happens for the
    # row under the cursor, and only while the pane is actually on screen.
    def pane
      Preview.new(current, current ? @previews.turns_for(current) : [], now: now)
    end

    def header
      total  = @sessions.size
      shown  = visible.size
      counts = +"#{shown}#{shown == total ? '' : "/#{total}"} chat#{'s' if total != 1}"
      counts << "  #{Ansi::RED}#{@marked.size} marked#{Ansi::RESET}" unless @marked.empty?
      counts << "  #{Ansi::CYAN}filter: #{@filter}#{Ansi::RESET}" unless @filter.empty?
      "#{Ansi::BOLD}Claude Code chats#{Ansi::RESET}  #{Ansi::DIM}#{counts}#{Ansi::RESET}"
    end

    def row(session, selected)
      meta  = meta_for(session)
      room  = [row_width - Ansi.length(meta) - META_WIDTH, TITLE_FLOOR].max
      title = Ansi.clip(session.title, room)
      line  = " #{mark_for(session)} #{title.ljust(room)}  #{Ansi::DIM}#{meta}#{Ansi::RESET}"

      selected ? "#{Ansi::REVERSE}#{Ansi.strip(line)}#{Ansi::RESET}" : line
    end

    def meta_for(session)
      columns = preview? ? COMPACT_PROJECT : PROJECT_WIDTH
      project = Ansi.clip(session.project, columns).ljust(columns)
      meta    = "#{session.age(now).rjust(9)}  #{project}  #{session.messages.to_s.rjust(4)} msg"
      preview? ? meta : "#{meta}  #{session.size.rjust(5)}"
    end

    def mark_for(session)
      if @marked.key?(session.id)
        "#{Ansi::RED}✗#{Ansi::RESET}"
      elsif session.live?
        "#{Ansi::GREEN}●#{Ansi::RESET}"
      else
        ' '
      end
    end

    # `o` — validated up front so a problem shows as a status line instead of
    # dropping the user into a dead shell.
    def stage_resume
      session = current or return

      @status = resume_blocker(session)
      @resume = session if @status.nil?
    end

    def resume_blocker(session)
      if !@launcher.available?
        'Cannot resume: `claude` is not on PATH.'
      elsif session.live?
        'That is the chat you are running in right now — resuming it would give two writers one transcript.'
      elsif session.messages.zero?
        'Cannot resume: this chat has no messages to resume from.'
      elsif session.working_dir.nil?
        "Cannot resume: original directory is gone (#{session.cwd || session.project})."
      end
    end

    def prompt_filter
      @terminal.write("#{Ansi.move_to(HEADER_ROWS + rows + 3)}#{Ansi::CLEAR_LINE}#{Ansi::CYAN}filter:#{Ansi::RESET} ")
      @filter = @terminal.read_line
      invalidate
    end

    def confirm_and_delete
      if @marked.empty?
        @status = 'Nothing marked — press d on a chat first.'
        return
      end

      victims = @marked.values.sort_by { |session| -session.mtime.to_f }
      show_confirmation(victims)

      unless @terminal.read_line.strip.downcase == CONFIRM_WORD
        @status = 'Cancelled — nothing was deleted.'
        return
      end

      @status = summarise(victims, delete(victims))
    end

    def show_confirmation(victims)
      lines = [
        confirmation_heading(victims), '',
        *victim_lines(victims), '',
        confirmation_warning, '',
        "Type #{Ansi::BOLD}#{CONFIRM_WORD}#{Ansi::RESET} to confirm (anything else cancels): "
      ]

      @terminal.write(Ansi::CLEAR_SCREEN + lines.join("\r\n"))
    end

    def confirmation_heading(victims)
      verb = @trash ? 'Move to trash' : 'Permanently delete'
      "#{Ansi::BOLD}#{verb} #{count(victims.size)}?#{Ansi::RESET}"
    end

    # Only as many as fit the screen; the rest are summarised on one line.
    def victim_lines(victims)
      lines = victims.first(rows).map do |session|
        "  #{Ansi::RED}✗#{Ansi::RESET} #{Ansi.clip(session.title, width - 34)}  " \
          "#{Ansi::DIM}#{session.project} · #{session.age(now)}#{Ansi::RESET}"
      end
      lines << "  #{Ansi::DIM}… and #{victims.size - rows} more#{Ansi::RESET}" if victims.size > rows
      lines
    end

    def confirmation_warning
      @trash ? "Files move to #{@paths.trash}." : 'This cannot be undone.'
    end

    def delete(victims)
      failures = victims.filter_map do |session|
        @trash ? move_to_trash(session) : remove(session)
        forget(session)
        nil
      rescue StandardError => e
        "#{session.id}: #{e.message}"
      end

      @visible = nil
      move(0)
      failures
    end

    def move_to_trash(session)
      dest = File.join(@paths.trash, "#{now.strftime('%Y%m%d-%H%M%S')}-#{session.id}")
      FileUtils.mkdir_p(dest)
      FileUtils.mv(session.path, dest)
      env_dir = session.env_dir
      FileUtils.mv(env_dir, dest) if env_dir
    end

    def remove(session)
      File.delete(session.path)
      env_dir = session.env_dir
      FileUtils.rm_rf(env_dir) if env_dir
    end

    def forget(session)
      @sessions.delete(session)
      @marked.delete(session.id)
      @previews.forget(session.id)
      @deleted += 1
    end

    def summarise(victims, failures)
      return "Deleted #{count(victims.size)}." if failures.empty?

      "Deleted #{victims.size - failures.size}, failed #{failures.size}: #{failures.first}"
    end

    def report
      return if @deleted.zero?

      where = @trash ? " (moved to #{@paths.trash})" : ''
      @terminal.write("Deleted #{count(@deleted)}#{where}.\n")
    end

    def count(number)
      "#{number} chat#{'s' if number != 1}"
    end
  end
end
