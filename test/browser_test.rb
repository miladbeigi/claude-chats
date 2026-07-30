# frozen_string_literal: true

require_relative 'test_helper'

module ClaudeChats
  class BrowserTest < TestCase
    NOW = Time.utc(2026, 7, 30, 12, 0, 0)

    # --- navigation ----------------------------------------------------------

    def test_cursor_starts_at_the_top_and_clamps_at_both_ends
      seed(3)

      assert_equal 'a', marked_id(keys: ['d'])
      assert_equal 'c', marked_id(keys: %w[j j j j j d]), 'cannot move past the last chat'
      assert_equal 'a', marked_id(keys: %w[k k k d]), 'cannot move above the first chat'
    end

    def test_arrow_keys_move_like_jk
      seed(3)

      assert_equal 'b', marked_id(keys: %w[down d])
      assert_equal 'a', marked_id(keys: %w[down up d])
    end

    def test_g_and_shift_g_jump_to_the_ends
      seed(4)

      assert_equal 'd', marked_id(keys: %w[G d])
      assert_equal 'a', marked_id(keys: %w[G g d])
    end

    def test_paging_moves_by_a_screen
      seed(30)
      terminal = drive(keys: %w[pgdn d], height: 12) # 12 rows => 7 list rows

      assert_equal %w[h], terminal_marks(terminal)
    end

    # The window has to follow the cursor, or selecting past the bottom row would
    # move an invisible highlight.
    def test_viewport_scrolls_to_keep_the_cursor_visible
      seed(30)
      terminal = drive(keys: (['j'] * 10), height: 12)
      shown    = list_titles(terminal)

      assert_includes shown.join(' '), 'chat k', 'cursor row must be on screen'
      refute_includes shown.join(' '), 'chat a', 'top of the list should have scrolled away'
    end

    # --- marking -------------------------------------------------------------

    def test_d_toggles_a_mark_and_advances
      seed(3)
      terminal = drive(keys: %w[d k d])

      assert_empty terminal_marks(terminal), 'second d on the same row unmarks it'
    end

    def test_space_marks_like_d
      seed(2)

      assert_equal 'a', marked_id(keys: [' '])
    end

    def test_shift_d_marks_everything_visible_and_u_clears
      seed(3)

      assert_equal %w[a b c], terminal_marks(drive(keys: ['D']))
      assert_empty terminal_marks(drive(keys: %w[D u]))
    end

    def test_header_reports_the_mark_count
      seed(3)

      assert_includes header(drive(keys: %w[d d])), '2 marked'
    end

    # --- filtering -----------------------------------------------------------

    def test_filter_narrows_the_list
      builder.chat(id: 'a', text: 'vault raft rollout', mtime: NOW - 10)
      builder.chat(id: 'b', text: 'pipeline debugging', mtime: NOW - 20)
      terminal = drive(keys: ['/'], answers: ['vault'])

      assert_includes header(terminal), '1/2 chats'
      assert_includes header(terminal), 'filter: vault'
      assert_equal ['vault raft rollout'], list_titles(terminal)
    end

    # After filtering, the cursor sits on the first *visible* row, so d must mark
    # that chat rather than whatever was at index 0 before.
    def test_marking_applies_to_the_filtered_row_not_the_original_index
      seed(3)

      assert_equal %w[b], terminal_marks(drive(keys: ['/', 'd'], answers: ['chat b']))
    end

    def test_escape_clears_the_filter_first_then_the_marks
      seed(3)
      terminal = drive(keys: ['/', 'D', 'esc'], answers: ['chat'])

      assert_equal %w[a b c], terminal_marks(terminal), 'first escape only drops the filter'
      refute_includes header(terminal), 'filter:'

      assert_empty terminal_marks(drive(keys: ['/', 'D', 'esc', 'esc'], answers: ['chat']))
    end

    # --- deletion ------------------------------------------------------------

    def test_enter_with_nothing_marked_explains_itself
      seed(2)

      assert_includes status(drive(keys: ['enter'])), 'Nothing marked'
      assert_equal %w[a b], transcripts
    end

    def test_deleting_requires_the_confirmation_word
      seed(2)
      terminal = drive(keys: %w[d enter], answers: ['no'])

      assert_includes status(terminal), 'Cancelled'
      assert_equal %w[a b], transcripts, 'nothing may be removed without confirmation'
    end

    def test_empty_answer_cancels
      seed(2)
      drive(keys: %w[d enter], answers: [''])

      assert_equal %w[a b], transcripts
    end

    def test_confirming_deletes_marked_transcripts_and_their_session_env
      seed(3)
      builder.session_env('a')
      builder.session_env('b')

      terminal = drive(keys: %w[d d enter], answers: ['YES  '])

      assert_equal %w[c], transcripts
      refute_path_exists File.join(paths.session_env, 'a'), 'orphaned session-env must go too'
      refute_path_exists File.join(paths.session_env, 'b')
      assert_includes status(terminal), 'Deleted 2 chats'
      assert_includes terminal.plain_output, 'Deleted 2 chats.'
    end

    def test_deleting_one_chat_reads_as_singular
      seed(2)

      assert_includes status(drive(keys: %w[d enter], answers: ['yes'])), 'Deleted 1 chat.'
    end

    def test_confirmation_screen_lists_what_will_go
      seed(2)
      terminal = drive(keys: %w[d enter], answers: ['no'])
      confirm  = terminal.frames.find { |frame| frame.include?('Permanently delete') }

      refute_nil confirm, 'expected a confirmation screen'
      assert_includes terminal.plain(confirm), 'chat a'
      assert_includes terminal.plain(confirm), 'This cannot be undone.'
    end

    def test_trash_mode_moves_files_instead_of_deleting_them
      seed(2)
      builder.session_env('a')
      terminal = drive(keys: %w[d enter], answers: ['yes'], trash: true)

      assert_equal %w[b], transcripts
      moved = Dir.glob(File.join(paths.trash, '*', '*'))

      assert_includes moved.map { |path| File.basename(path) }, 'a.jsonl'
      assert_includes moved.map { |path| File.basename(path) }, 'a'
      assert_includes terminal.plain(terminal.frames.find { |f| f.include?('Move to trash') }), paths.trash
    end

    def test_trash_directory_is_named_from_the_clock
      seed(1)
      drive(keys: %w[d enter], answers: ['yes'], trash: true)

      assert_equal ['20260730-120000-a'], Dir.children(paths.trash)
    end

    def test_a_failing_delete_is_reported_and_the_chat_stays
      seed(2)
      FileUtils.chmod(0o500, File.join(paths.projects, TranscriptBuilder::DEFAULT_PROJECT))
      terminal = drive(keys: %w[d enter], answers: ['yes'])

      assert_includes status(terminal), 'failed 1'
      assert_equal %w[a b], transcripts
    ensure
      FileUtils.chmod(0o700, File.join(paths.projects, TranscriptBuilder::DEFAULT_PROJECT))
    end

    # --- resuming ------------------------------------------------------------

    def test_o_hands_back_the_session_to_resume
      builder.chat(id: 'a', cwd: tmp)
      launcher = FakeLauncher.new
      session  = run_browser(drive_terminal(keys: ['o']), launcher: launcher)

      refute_nil session
      assert_equal 'a', session.id
    end

    def test_o_refuses_when_claude_is_not_installed
      builder.chat(id: 'a', cwd: tmp)
      terminal = drive(keys: ['o'], launcher: FakeLauncher.new(available: false))

      assert_includes status(terminal), 'not on PATH'
    end

    def test_o_refuses_the_currently_running_chat
      builder.chat(id: 'a', cwd: tmp)
      env['CLAUDE_CODE_SESSION_ID'] = 'a'
      terminal = drive(keys: ['o'])

      assert_includes status(terminal), 'running in right now'
    end

    def test_o_refuses_a_chat_with_no_messages
      builder.write(id: 'a', records: [builder.ai_title('Titles only')])
      terminal = drive(keys: ['o'])

      assert_includes status(terminal), 'no messages'
    end

    def test_o_refuses_when_the_original_directory_is_gone
      builder.chat(id: 'a', cwd: '/tmp/definitely-gone-c3f2', project: '-tmp-gone-c3f2')
      terminal = drive(keys: ['o'])

      assert_includes status(terminal), 'original directory is gone'
    end

    def test_the_running_chat_is_flagged_in_the_list
      seed(2)
      env['CLAUDE_CODE_SESSION_ID'] = 'a'

      assert_includes drive(keys: []).last_frame, '●'
    end

    # --- rendering -----------------------------------------------------------

    # A row exactly as wide as the terminal soft-wraps and pushes the layout
    # down a line, which this guards against.
    def test_no_rendered_line_reaches_the_terminal_width
      seed(5)
      builder.chat(id: 'zz', text: 'x' * 400, cwd: "/tmp/#{'y' * 200}", mtime: NOW)

      [40, 60, 100, 173, 240].each do |width|
        terminal = drive(keys: [], width: width)
        longest  = terminal.last_frame_lines.map(&:length).max

        assert_operator longest, :<, width, "a line filled the #{width}-column screen"
      end
    end

    # Two chats or twenty, the list occupies the same block of the screen, so the
    # help line never moves under the user.
    def test_screen_is_padded_to_a_stable_height
      seed(2)
      few = drive(keys: [], height: 20).last_frame_lines.size
      seed(25)
      many = drive(keys: [], height: 20).last_frame_lines.size

      assert_equal few, many
      assert_operator few, :<=, 20, 'the frame must fit the terminal'
    end

    def test_a_status_message_uses_the_reserved_final_line
      seed(2)
      quiet  = drive(keys: [], height: 20).last_frame_lines.size
      noisy  = drive(keys: ['enter'], height: 20).last_frame_lines.size

      assert_equal quiet + 1, noisy
      assert_operator noisy, :<=, 20, 'the status line must not push the screen down'
    end

    # At 40 columns the metadata no longer fits, but the title still has to be
    # readable and every chat still has to have a row.
    def test_narrow_terminals_still_render_every_row
      seed(3)
      frame = drive(keys: [], width: 40).last_frame

      %w[a b c].each { |id| assert_includes frame, "chat #{id}" }
    end

    def test_short_terminals_still_show_some_rows
      seed(10)

      refute_empty list_titles(drive(keys: [], height: 6))
    end

    def test_help_line_is_always_visible
      seed(1)

      assert_includes drive(keys: []).last_frame, 'Enter delete marked'
    end

    # --- lifecycle -----------------------------------------------------------

    def test_quitting_restores_the_terminal
      seed(1)
      terminal = drive(keys: ['q'])

      assert_equal 1, terminal.alt_screens
      assert_equal 1, terminal.restores
    end

    def test_ctrl_c_quits
      seed(1)
      terminal = drive(keys: ['ctrl_c'])

      assert_equal 1, terminal.restores
      assert_equal %w[a], transcripts
    end

    def test_no_chats_says_so_without_entering_the_ui
      terminal = drive_terminal(keys: [])
      session  = Browser.new([], terminal: terminal, paths: paths,
                                 launcher: FakeLauncher.new).run

      assert_nil session
      assert_includes terminal.output, 'No Claude Code chats found.'
      assert_equal 0, terminal.alt_screens
    end

    def test_without_a_tty_it_only_lists
      seed(2)
      terminal = FakeTerminal.new(tty: false)
      Browser.new(load_sessions(clock: clock_at(NOW)), terminal: terminal,
                                                       paths: paths, launcher: FakeLauncher.new).run

      assert_includes terminal.output, 'chat a'
      assert_includes terminal.errors, 'Not a TTY'
      assert_equal 0, terminal.alt_screens
    end

    private

    def seed(count)
      ('a'..'z').first(count).each_with_index do |letter, index|
        builder.chat(id: letter, text: "chat #{letter}", mtime: NOW - index)
      end
    end

    def drive_terminal(keys:, answers: [], width: 100, height: 20)
      FakeTerminal.new(keys: keys.dup, answers: answers.dup, width: width, height: height)
    end

    def run_browser(terminal, launcher: FakeLauncher.new, trash: false)
      Browser.new(load_sessions(clock: clock_at(NOW)),
                  terminal: terminal, paths: paths, launcher: launcher,
                  trash: trash, clock: clock_at(NOW)).run
    end

    def drive(keys:, answers: [], width: 100, height: 20, trash: false, launcher: FakeLauncher.new)
      terminal = drive_terminal(keys: keys, answers: answers, width: width, height: height)
      run_browser(terminal, launcher: launcher, trash: trash)
      terminal
    end

    def header(terminal)
      terminal.last_frame_lines.first.to_s
    end

    def status(terminal)
      terminal.last_frame_lines.last.to_s
    end

    # Titles of the rows currently on screen, metadata and mark stripped. Relies
    # on the metadata block, so only use it at widths where rows are not cut.
    def list_titles(terminal)
      terminal.last_frame_lines
              .select { |line| line.include?(' msg ') }
              .map { |line| line.sub(/\A\s*[✗●]?\s*/, '').split(/\s{2,}/).first.to_s.strip }
    end

    def terminal_marks(terminal)
      terminal.last_frame_lines.filter_map { |line| line[/✗ chat (\w+)/, 1] }.sort
    end

    def marked_id(keys:)
      terminal_marks(drive(keys: keys)).first
    end
  end
end
