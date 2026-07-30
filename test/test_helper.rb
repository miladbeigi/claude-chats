# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'claude_chats'

require 'fileutils'
require 'minitest/autorun'
require 'tmpdir'

require_relative 'support/fake_launcher'
require_relative 'support/fake_terminal'
require_relative 'support/transcript_builder'

module ClaudeChats
  # Base class giving every test its own throwaway Claude home.
  class TestCase < Minitest::Test
    REAL_HOME = File.expand_path(Paths::DEFAULT_HOME)

    # Struct is enough for a clock: it answers #now with a fixed time.
    FrozenClock = Struct.new(:now)

    attr_reader :tmp, :env, :paths, :builder

    def setup
      @tmp     = Dir.mktmpdir('claude-chats-test')
      @env     = { 'CLAUDE_CONFIG_DIR' => @tmp, 'PATH' => '' }
      @paths   = Paths.new(env: @env)
      @builder = TranscriptBuilder.new(@paths)

      refute_real_home
      FileUtils.mkdir_p(@paths.projects)
    end

    def teardown
      FileUtils.remove_entry(@tmp) if @tmp && File.directory?(@tmp)
    end

    # Hard stop: no bug in a fixture may let a test reach the real chats.
    def refute_real_home
      home = @paths.home
      return unless home == REAL_HOME || home.start_with?("#{REAL_HOME}#{File::SEPARATOR}")

      raise "test paths resolved inside the real Claude home: #{home}"
    end

    def clock_at(time)
      FrozenClock.new(time)
    end

    def load_sessions(clock: Time)
      SessionLoader.new(paths: @paths, clock: clock).load_all
    end

    def transcripts
      Dir.glob(File.join(@paths.projects, '*', '*.jsonl')).map { |path| File.basename(path, '.jsonl') }.sort
    end

    # A real executable named claude, so Launcher's PATH walk can find one.
    def stub_claude_on_path
      bin = File.join(@tmp, 'bin')
      FileUtils.mkdir_p(bin)
      script = File.join(bin, 'claude')
      File.write(script, "#!/bin/sh\necho stub\n")
      FileUtils.chmod(0o755, script)
      @env['PATH'] = bin
      script
    end
  end
end
