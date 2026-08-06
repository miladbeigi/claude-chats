# frozen_string_literal: true

require_relative 'test_helper'

module ClaudeChats
  # The tail read and the pane rendering. Both are exercised against synthetic
  # transcripts; the pane's place on the screen is covered in browser_test.rb.
  class PreviewTest < TestCase
    NOW = Time.utc(2026, 7, 30, 12, 0, 0)
    CAPTION_ROWS = Preview::CAPTION_ROWS

    # --- what counts as a turn -----------------------------------------------

    def test_shows_the_last_turns_oldest_first
      write('first question', 'first answer', 'second question', 'second answer')

      assert_equal [[:claude, 'first answer'], [:you, 'second question'], [:claude, 'second answer']],
                   roles_and_text(turns)
    end

    def test_keeps_only_the_last_few_turns
      write(*Array.new(10) { |i| "message #{i}" })

      assert_equal 3, turns.size
      assert_equal 'message 9', turns.last.text
    end

    # An assistant record carrying only a tool_use, or a user record carrying a
    # tool_result, has no text — which is most of a real transcript.
    def test_skips_tool_calls_and_their_results
      builder.write(id: 'a', mtime: NOW, records: [
                      builder.user('run the tests'),
                      builder.tool_use('Bash'),
                      builder.tool_result('42 examples, 0 failures'),
                      builder.assistant('all green')
                    ])

      assert_equal [[:you, 'run the tests'], [:claude, 'all green']], roles_and_text(turns)
    end

    def test_skips_sidechain_turns
      builder.write(id: 'a', mtime: NOW, records: [
                      builder.user('main thread'),
                      builder.user('subagent chatter', sidechain: true),
                      builder.assistant('subagent reply', sidechain: true)
                    ])

      assert_equal ['main thread'], turns.map(&:text)
    end

    def test_skips_slash_command_and_hook_wrappers
      builder.write(id: 'a', mtime: NOW, records: [
                      builder.user('real message'),
                      builder.caveat,
                      builder.command_output('some stdout')
                    ])

      assert_equal ['real message'], turns.map(&:text)
    end

    def test_a_slash_command_reads_as_its_name
      builder.write(id: 'a', mtime: NOW, records: [builder.slash_command('/exit')])

      assert_equal ['/exit'], turns.map(&:text)
    end

    # --- the bounded tail read -----------------------------------------------

    # The last window of an agentic chat is often nothing but tool calls, so the
    # loader has to widen it rather than report an empty preview.
    def test_widens_the_window_when_the_tail_holds_no_prose
      builder.write(id: 'a', mtime: NOW, records: [
                      builder.user('the only thing anyone said'),
                      *Array.new(60) { builder.tool_use('Bash') }
                    ])

      assert_operator File.size(transcript_path('a')), :>, 512, 'fixture must exceed the window'
      assert_equal ['the only thing anyone said'], turns(window: 512).map(&:text)
    end

    # Seeking lands mid-line. Half a record must be dropped, not parsed as one.
    def test_a_record_cut_by_the_window_boundary_is_dropped
      builder.write(id: 'a', mtime: NOW, records: [builder.user('x' * 400)])

      # No room to widen, so the only record is the one the window bisects.
      assert_empty turns(window: 64, max_window: 64)
    end

    def test_reads_the_whole_file_when_it_fits_inside_the_window
      write('short and sweet')

      assert_equal ['short and sweet'], turns(window: 1_048_576).map(&:text)
    end

    def test_unparseable_lines_and_invalid_bytes_are_skipped_not_fatal
      builder.write_lines(id: 'a', mtime: NOW, lines: [
                            'not json at all',
                            '{"type":"user","message":{"role":"user","content":"tru',
                            +"{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"bad \xff byte\"}}",
                            JSON.generate(builder.user('the good one'))
                          ])

      # The first two lines are not records. The third is, once its bad byte is
      # scrubbed, so it survives rather than being thrown away.
      assert_equal ["bad \u{FFFD} byte", 'the good one'], turns.map(&:text)
    end

    def test_a_missing_transcript_reports_unavailable
      write('gone in a moment')
      session = sessions.first
      File.delete(session.path)

      assert_equal PreviewLoader::UNAVAILABLE, PreviewLoader.new(paths: paths).turns_for(session)
    end

    def test_the_same_chat_is_only_read_once
      write('cache me')
      loader  = PreviewLoader.new(paths: paths)
      session = sessions.first
      loader.turns_for(session)
      File.write(session.path, JSON.generate(builder.user('changed on disk')))

      assert_equal ['cache me'], loader.turns_for(session).map(&:text)
      assert_equal ['changed on disk'], loader.tap { |l| l.forget(session.id) }.turns_for(session).map(&:text)
    end

    # --- rendering -----------------------------------------------------------

    # Message text is pasted from anywhere, so it can carry escape sequences that
    # would move the cursor or recolour the rest of the screen.
    def test_escape_sequences_are_stripped_from_preview_text
      write("\e[31mred\e[0m and \e]777;notify;hi\a done")
      text = plain(pane_lines(width: 60, rows: 6))

      assert_includes text, 'red and done'
      refute_includes text, "\e"
      refute_includes text, "\a"
    end

    # Who said what should be readable from the colour alone, without stopping to
    # read the label, so the colour covers the message rather than just its name.
    def test_the_two_speakers_get_different_colours
      write('a question', 'an answer')
      pane = pane_lines(width: 40, rows: 6)

      assert_includes pane, "#{Ansi::CYAN}   you  a question#{Ansi::RESET}"
      assert_includes pane, "#{Ansi::MAGENTA}claude  an answer#{Ansi::RESET}"
    end

    def test_a_wrapped_message_keeps_its_colour_on_every_line
      write('one two three four five six seven eight nine ten eleven twelve')
      body = pane_lines(width: 30, rows: 8).drop(CAPTION_ROWS).reject { |line| Ansi.strip(line).strip.empty? }

      assert_operator body.size, :>, 1, 'expected the message to wrap'
      assert(body.all? { |line| line.start_with?(Ansi::CYAN) && line.end_with?(Ansi::RESET) })
    end

    # The label is coloured, not padded with escape codes: colouring it must not
    # push the text out of the pane.
    def test_colouring_the_label_does_not_change_the_layout
      write('one two three four five six seven eight nine ten')
      lines = pane_lines(width: 30, rows: 8)

      assert_operator lines.map { |line| Ansi.length(line) }.max, :<=, 30
    end

    def test_wraps_text_into_the_pane_width
      write('one two three four five six seven eight nine ten eleven twelve')
      lines = pane_lines(width: 30, rows: 8)

      assert_operator plain(lines).split("\n").map(&:length).max, :<=, 30
      assert_includes plain(lines), 'one two'
    end

    def test_a_word_too_long_to_fit_is_broken
      write("/#{'nested/' * 20}file.rb")
      lines = pane_lines(width: 28, rows: 8)

      assert_operator plain(lines).split("\n").map(&:length).max, :<=, 28
      assert_includes plain(lines), 'nested/'
    end

    def test_a_long_turn_is_capped_and_the_cut_is_marked
      write((1..80).map { |n| "word#{n}" }.join(' '))
      lines = plain(pane_lines(width: 30, rows: 20))

      assert_includes lines, '…'
      refute_includes lines, 'word80'
    end

    def test_the_pane_is_always_exactly_as_tall_as_asked
      write('a short exchange', 'and a reply')

      [4, 8, 20].each do |rows|
        assert_equal rows, pane_lines(width: 40, rows: rows).size, "#{rows} rows requested"
      end
    end

    # The newest turn is the one that says what the chat became, so a short pane
    # drops the oldest lines rather than the newest.
    def test_a_short_pane_keeps_the_newest_turn
      write('the oldest thing said', 'the newest thing said')
      text = plain(pane_lines(width: 40, rows: 3)) # caption, blank, one turn

      assert_includes text, 'the newest thing said'
      refute_includes text, 'the oldest thing said'
    end

    def test_the_caption_names_the_project_age_and_message_count
      write('hello')

      assert_includes plain(pane_lines(width: 40, rows: 6)), 'demo · 0s ago · 1 msg'
    end

    def test_an_empty_chat_says_so
      builder.write(id: 'a', mtime: NOW, records: [builder.ai_title('titled but silent')])

      assert_includes plain(pane_lines(width: 40, rows: 6)), Preview::EMPTY
    end

    def test_a_chat_with_no_prose_says_so
      builder.write(id: 'a', mtime: NOW, records: [builder.user('hi'), builder.tool_use('Bash')])

      preview = Preview.new(sessions.first, [], now: NOW)

      assert_includes plain(preview.lines(width: 40, rows: 6)), Preview::NO_TEXT
    end

    def test_no_highlighted_row_renders_a_blank_pane
      lines = Preview.new(nil, [], now: NOW).lines(width: 40, rows: 5)

      assert_equal 5, lines.size
      assert_equal '', plain(lines).strip
    end

    def test_beside_lines_up_the_divider_in_one_column
      write('hello there')
      left  = ['a short line', "#{Ansi::REVERSE}a coloured one#{Ansi::RESET}", '']
      built = preview.beside(left, list_width: 20, width: 60)

      bars = built.map { |line| Ansi.strip(line).index('│') }

      # The bar sits inside the divider, so one column past the padded list.
      assert_equal [21, 21, 21], bars
      assert(built.all? { |line| Ansi.length(line) <= 60 })
    end

    private

    def write(*texts)
      records = texts.each_with_index.map do |text, index|
        index.even? ? builder.user(text) : builder.assistant(text)
      end
      builder.write(id: 'a', records: records, mtime: NOW)
    end

    def transcript_path(id)
      File.join(paths.projects, TranscriptBuilder::DEFAULT_PROJECT, "#{id}.jsonl")
    end

    def sessions
      load_sessions(clock: clock_at(NOW))
    end

    def roles_and_text(turns)
      turns.map { |turn| [turn.role, turn.text] }
    end

    def turns(**options)
      PreviewLoader.new(paths: paths, **options).turns_for(sessions.first)
    end

    def preview
      session = sessions.first
      Preview.new(session, PreviewLoader.new(paths: paths).turns_for(session), now: NOW)
    end

    def pane_lines(width:, rows:)
      preview.lines(width: width, rows: rows)
    end

    def plain(lines)
      Ansi.strip(lines.join("\n"))
    end
  end
end
