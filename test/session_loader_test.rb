# frozen_string_literal: true

require_relative 'test_helper'

module ClaudeChats
  class SessionLoaderTest < TestCase
    def test_reads_first_human_prompt_as_title
      builder.chat(id: 'a', text: 'why is the deploy stuck?')

      assert_equal 'why is the deploy stuck?', only_session.title
    end

    def test_custom_title_wins_over_everything
      builder.chat(id: 'a', text: 'first prompt', extra: [
                     builder.ai_title('Generated title'),
                     builder.custom_title('my-own-name')
                   ])

      assert_equal 'my-own-name', only_session.title
    end

    def test_ai_title_wins_over_first_prompt
      builder.chat(id: 'a', text: 'first prompt', extra: [builder.ai_title('Generated title')])

      assert_equal 'Generated title', only_session.title
    end

    # A chat where the user only ran a slash command has no prose to show, so the
    # command name is the most useful thing left.
    def test_falls_back_to_slash_command_name
      builder.write(id: 'a', records: [
                      builder.caveat,
                      builder.slash_command('/exit'),
                      builder.command_output('Bye!')
                    ])

      assert_equal '/exit', only_session.title
    end

    def test_falls_back_to_placeholder_when_nothing_usable
      builder.write(id: 'a', records: [builder.caveat])

      assert_equal SessionLoader::NO_MESSAGES, only_session.title
    end

    def test_wrapper_records_are_not_counted_as_messages
      builder.write(id: 'a', records: [
                      builder.caveat,
                      builder.slash_command('/exit'),
                      builder.command_output('Bye!')
                    ])

      assert_equal 1, only_session.messages, 'only the command itself should count'
    end

    def test_subagent_records_are_ignored
      builder.write(id: 'a', records: [
                      builder.user('main question'),
                      builder.user('subagent chatter', sidechain: true),
                      builder.assistant('subagent answer', sidechain: true)
                    ])
      session = only_session

      assert_equal 1, session.messages
      assert_equal 'main question', session.title
      refute_predicate session, :sidechain_only?
    end

    def test_transcript_with_only_titles_has_no_messages
      builder.write(id: 'a', records: [builder.ai_title('Titles only')])
      session = only_session

      assert_equal 0, session.messages
      assert_predicate session, :sidechain_only?
    end

    def test_unparseable_lines_are_skipped_not_fatal
      path = builder.chat(id: 'a', text: 'good line')
      File.write(path, "#{File.read(path)}not json at all\n{\"type\":\n")

      assert_equal 'good line', only_session.title
    end

    def test_non_object_json_lines_are_ignored
      path = builder.chat(id: 'a', text: 'good line')
      File.write(path, "[1,2,3]\n#{File.read(path)}")

      assert_equal 'good line', only_session.title
    end

    def test_captures_cwd_and_branch
      builder.write(id: 'a', records: [builder.user('hi', cwd: '/tmp/somewhere', branch: 'feature/x')])
      session = only_session

      assert_equal '/tmp/somewhere', session.cwd
      assert_equal 'feature/x', session.branch
    end

    def test_missing_file_returns_nil
      assert_nil SessionLoader.new(paths: paths).parse(File.join(paths.projects, 'gone.jsonl'))
    end

    def test_load_all_sorts_newest_first
      now = Time.now
      builder.chat(id: 'old', text: 'old', mtime: now - 3600)
      builder.chat(id: 'new', text: 'new', mtime: now - 10)
      builder.chat(id: 'middle', text: 'middle', mtime: now - 600)

      assert_equal %w[new middle old], load_sessions.map(&:id)
    end

    def test_load_all_spans_every_project_directory
      builder.chat(id: 'a', project: '-tmp-one')
      builder.chat(id: 'b', project: '-tmp-two')

      assert_equal %w[a b], load_sessions.map(&:id).sort
    end

    def test_ignores_non_transcript_files
      FileUtils.mkdir_p(File.join(paths.projects, '-tmp-demo', 'memory'))
      File.write(File.join(paths.projects, '-tmp-demo', 'memory', 'note.md'), 'not a transcript')
      builder.chat(id: 'a')

      assert_equal %w[a], load_sessions.map(&:id)
    end

    private

    def only_session
      sessions = load_sessions

      assert_equal 1, sessions.size, 'expected exactly one fixture session'
      sessions.first
    end
  end
end
