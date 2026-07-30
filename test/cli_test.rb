# frozen_string_literal: true

require_relative 'test_helper'

module ClaudeChats
  class CLITest < TestCase
    NOW = Time.utc(2026, 7, 30, 12, 0, 0)

    def test_version
      terminal = FakeTerminal.new

      assert_equal 0, run_cli(%w[--version], terminal)
      assert_equal "claude-chats #{VERSION}\n", terminal.output
    end

    def test_help_lists_every_flag
      terminal = FakeTerminal.new

      assert_equal 0, run_cli(%w[--help], terminal)
      %w[--trash --project --list --version --help].each do |flag|
        assert_includes terminal.output, flag
      end
    end

    def test_unknown_flag_fails_with_a_hint
      terminal = FakeTerminal.new

      assert_equal 1, run_cli(%w[--nope], terminal)
      assert_includes terminal.errors, 'invalid option'
      assert_includes terminal.errors, '--help'
    end

    def test_missing_projects_directory_is_an_error
      FileUtils.remove_entry(paths.projects)
      terminal = FakeTerminal.new

      assert_equal 1, run_cli([], terminal)
      assert_includes terminal.errors, 'No Claude projects directory'
    end

    def test_list_prints_one_line_per_chat_newest_first
      builder.chat(id: 'older', text: 'older chat', mtime: NOW - 600)
      builder.chat(id: 'newer', text: 'newer chat', mtime: NOW - 10)
      terminal = FakeTerminal.new

      assert_equal 0, run_cli(%w[--list], terminal)
      titles = terminal.output.lines.map(&:strip)

      assert_equal 2, titles.size
      assert_includes titles[0], 'newer chat'
      assert_includes titles[1], 'older chat'
    end

    def test_list_with_no_chats_prints_nothing
      terminal = FakeTerminal.new

      assert_equal 0, run_cli(%w[--list], terminal)
      assert_empty terminal.output
    end

    def test_project_filter_matches_project_name
      builder.chat(id: 'a', project: '-tmp-alpha', cwd: '/tmp/alpha')
      builder.chat(id: 'b', project: '-tmp-beta', cwd: '/tmp/beta')
      terminal = FakeTerminal.new

      run_cli(%w[--list --project alpha], terminal)

      assert_equal 1, terminal.output.lines.size
      assert_includes terminal.output, 'alpha'
    end

    def test_project_filter_matches_the_full_directory
      builder.chat(id: 'a', project: '-tmp-alpha', cwd: '/Users/someone/work/infra')
      builder.chat(id: 'b', project: '-tmp-beta', cwd: '/tmp/beta')
      terminal = FakeTerminal.new

      run_cli(%w[--list --project someone/work], terminal)

      assert_equal 1, terminal.output.lines.size
    end

    def test_project_filter_can_match_nothing
      builder.chat(id: 'a')
      terminal = FakeTerminal.new

      assert_equal 0, run_cli(%w[--list --project nothing-like-this], terminal)
      assert_empty terminal.output
    end

    def test_interactive_run_without_a_resume_returns_success
      builder.chat(id: 'a')
      terminal = FakeTerminal.new(keys: ['q'])

      assert_equal 0, run_cli([], terminal)
      assert_equal 1, terminal.restores
    end

    # Pressing o in the browser has to reach the launcher, and only after the
    # alternate screen is torn down.
    def test_resume_launches_claude_and_announces_it
      builder.chat(id: 'a', cwd: tmp)
      terminal = FakeTerminal.new(keys: ['o'])
      launcher = FakeLauncher.new

      assert_equal 0, run_cli([], terminal, launcher: launcher)
      assert_equal [{ id: 'a', dir: tmp }], launcher.resumed
      assert_includes terminal.plain_output, 'Resuming'
      assert_includes terminal.plain_output, 'claude --resume a'
      assert_equal 1, terminal.restores
    end

    def test_a_failed_launch_is_reported_and_fails
      builder.chat(id: 'a', cwd: tmp)
      terminal = FakeTerminal.new(keys: ['o'])
      launcher = FakeLauncher.new(error: Errno::ENOENT.new('claude'))

      assert_equal 1, run_cli([], terminal, launcher: launcher)
      assert_includes terminal.errors, 'Failed to launch claude'
    end

    def test_trash_flag_reaches_the_browser
      builder.chat(id: 'a')
      terminal = FakeTerminal.new(keys: %w[d enter], answers: ['yes'])

      assert_equal 0, run_cli(%w[--trash], terminal)
      assert_empty transcripts
      refute_empty Dir.glob(File.join(paths.trash, '*', 'a.jsonl')), 'expected the chat in the trash'
    end

    def test_help_mentions_the_trash_location
      terminal = FakeTerminal.new
      run_cli(%w[--help], terminal)

      assert_includes terminal.output, paths.trash
    end

    private

    def run_cli(argv, terminal, launcher: FakeLauncher.new)
      CLI.new(argv, paths: paths, terminal: terminal, launcher: launcher, clock: clock_at(NOW)).run
    end
  end
end
