# frozen_string_literal: true

module ClaudeChats
  # Where Claude Code keeps its state on disk.
  #
  # Resolved per instance rather than baked into constants at load time, so a
  # caller (or a test) can point the whole app at a different directory by
  # passing a different environment.
  class Paths
    DEFAULT_HOME = '~/.claude'

    attr_reader :env

    def initialize(env: ENV)
      @env = env
    end

    def home
      File.expand_path(env['CLAUDE_CONFIG_DIR'] || DEFAULT_HOME)
    end

    def projects
      File.join(home, 'projects')
    end

    def session_env
      File.join(home, 'session-env')
    end

    def trash
      File.join(home, 'trash')
    end

    # Per-session scratch directory, or nil when the session has none.
    def session_env_for(session_id)
      dir = File.join(session_env, session_id.to_s)
      dir if File.directory?(dir)
    end

    # Set by Claude Code inside a running session, so a chat can recognise
    # itself and refuse to be resumed or reported as safe to delete.
    def live_session_id
      env['CLAUDE_CODE_SESSION_ID']
    end

    def path_entries
      env['PATH'].to_s.split(File::PATH_SEPARATOR).reject(&:empty?)
    end
  end
end
