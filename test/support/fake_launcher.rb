# frozen_string_literal: true

module ClaudeChats
  # Records what would have been launched instead of replacing the process.
  class FakeLauncher
    attr_reader :resumed

    def initialize(available: true, error: nil)
      @available = available
      @error     = error
      @resumed   = []
    end

    def available?
      @available
    end

    def claude_bin
      @available ? '/fake/bin/claude' : nil
    end

    def command_for(session)
      "claude --resume #{session.id}"
    end

    def resume(session)
      raise @error if @error

      @resumed << { id: session.id, dir: session.working_dir }
    end
  end
end
