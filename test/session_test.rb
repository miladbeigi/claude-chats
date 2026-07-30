# frozen_string_literal: true

require_relative 'test_helper'

module ClaudeChats
  class SessionTest < TestCase
    NOW = Time.utc(2026, 7, 30, 12, 0, 0)

    def test_age_buckets
      assert_equal '0s ago',     age_of(NOW)
      assert_equal '59s ago',    age_of(NOW - 59)
      assert_equal '1m ago',     age_of(NOW - 60)
      assert_equal '59m ago',    age_of(NOW - (59 * 60))
      assert_equal '1h ago',     age_of(NOW - 3600)
      assert_equal '23h ago',    age_of(NOW - (23 * 3600))
      assert_equal '1d ago',     age_of(NOW - 86_400)
      assert_equal '29d ago',    age_of(NOW - (29 * 86_400))
      assert_equal '2026-05-31', age_of(NOW - (60 * 86_400)), 'beyond a month, show the date'
    end

    def test_size_formatting
      assert_equal '0B', build(bytes: 0).size
      assert_equal '1023B', build(bytes: 1023).size
      assert_equal '1K', build(bytes: 1024).size
      assert_equal '512K', build(bytes: 524_288).size
      assert_equal '1.0M', build(bytes: 1_048_576).size
      assert_equal '2.5M', build(bytes: 2_621_440).size
    end

    def test_project_prefers_recorded_cwd
      assert_equal 'infra', build(cwd: '/Users/someone/work/infra').project
    end

    def test_project_decodes_directory_name_when_cwd_is_missing
      session = build(cwd: nil, project_dir: '/somewhere/projects/-Users-someone-work')

      assert_equal 'Users/someone/work', session.project
    end

    def test_working_dir_uses_cwd_when_it_exists
      assert_equal tmp, build(cwd: tmp).working_dir
    end

    # The encoded directory name is lossy, so it is only usable when it happens
    # to decode back to a directory that really exists.
    def test_working_dir_falls_back_to_decoded_project_dir
      dir = File.join(Dir.tmpdir, "ccfallback#{Process.pid}")
      skip "temp directory contains a dash: #{dir}" if dir.include?('-')

      FileUtils.mkdir_p(dir)
      session = build(cwd: '/tmp/definitely-gone-c3f2', project_dir: "/x/projects/#{dir.tr('/', '-')}")

      assert_equal dir, session.working_dir
    ensure
      FileUtils.remove_entry(dir) if dir && File.directory?(dir)
    end

    # Dashes inside a real path segment decode back to slashes, so the encoded
    # name cannot be trusted — better to report no directory than the wrong one.
    def test_working_dir_gives_up_when_the_encoded_name_is_ambiguous
      session = build(cwd: nil, project_dir: "/x/projects/#{tmp.tr('/', '-')}")

      assert_nil session.working_dir, "#{tmp} contains dashes, so it cannot round-trip"
    end

    def test_working_dir_is_nil_when_nothing_resolves
      session = build(cwd: '/tmp/definitely-gone-c3f2', project_dir: '/x/projects/-tmp-also-gone-c3f2')

      assert_nil session.working_dir
    end

    def test_live_is_true_only_for_the_running_session
      env['CLAUDE_CODE_SESSION_ID'] = 'abc'

      assert_predicate build(id: 'abc'), :live?
      refute_predicate build(id: 'def'), :live?
    end

    def test_live_is_false_when_no_session_is_running
      refute_predicate build(id: 'abc'), :live?
    end

    def test_env_dir_is_found_only_when_present
      builder.session_env('abc')

      assert_equal File.join(paths.session_env, 'abc'), build(id: 'abc').env_dir
      assert_nil build(id: 'def').env_dir
    end

    def test_matches_searches_title_project_cwd_and_id
      session = build(id: 'deadbeef', title: 'Fix the deploy', cwd: '/Users/someone/work/infra')

      assert session.matches?('deploy'), 'title'
      assert session.matches?('DEPLOY'), 'case insensitive'
      assert session.matches?('infra'), 'project'
      assert session.matches?('/work/'), 'cwd'
      assert session.matches?('deadbeef'), 'id'
      assert session.matches?(''), 'empty query matches everything'
      assert session.matches?(nil), 'nil query matches everything'
      refute session.matches?('rollback')
    end

    def test_to_line_keeps_columns_aligned
      lines = [
        build(title: 'short', cwd: '/tmp/demo', messages: 3, bytes: 400),
        build(title: 'much longer title here', cwd: '/tmp/a-very-long-project-name-here', messages: 1234,
              bytes: 9_999_999)
      ].map { |session| session.to_line(NOW) }

      prefixes = lines.map { |line| line[0, 45] }

      assert_equal 1, prefixes.map(&:length).uniq.size
      assert(lines.all? { |line| line.include?(' msg  ') })
    end

    private

    def age_of(mtime)
      build(mtime: mtime).age(NOW)
    end

    def build(**overrides)
      defaults = {
        path: File.join(paths.projects, '-tmp-demo', 'abc.jsonl'),
        id: 'abc',
        project_dir: File.join(paths.projects, '-tmp-demo'),
        title: 'a chat',
        mtime: NOW,
        bytes: 100,
        messages: 2,
        cwd: '/tmp/demo',
        paths: paths,
        clock: clock_at(NOW)
      }
      Session.new(**defaults.merge(overrides))
    end
  end
end
