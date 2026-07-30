# frozen_string_literal: true

module ClaudeChats
  # Hands the terminal over to `claude --resume`.
  #
  # This replaces the current process, so the user lands in a normal Claude
  # session and returns to their shell — not to this browser — when they quit.
  class Launcher
    COMMAND = 'claude'

    def initialize(paths: Paths.new)
      @paths = paths
    end

    def claude_bin
      return @claude_bin if defined?(@claude_bin)

      @claude_bin = @paths.path_entries
                          .map { |dir| File.join(dir, COMMAND) }
                          .find { |bin| File.file?(bin) && File.executable?(bin) }
    end

    def available?
      !claude_bin.nil?
    end

    def command_for(session)
      "#{COMMAND} --resume #{session.id}"
    end

    def resume(session)
      Dir.chdir(session.working_dir)
      exec(claude_bin, '--resume', session.id)
    end
  end
end
