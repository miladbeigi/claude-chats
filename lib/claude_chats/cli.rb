# frozen_string_literal: true

module ClaudeChats
  # Argument parsing and the top-level flow. Returns an exit status rather than
  # calling exit, so the whole command is testable in-process.
  class CLI
    SUCCESS = 0
    FAILURE = 1

    def initialize(argv, paths: Paths.new, terminal: Terminal.new, launcher: nil, clock: Time)
      @argv     = argv
      @paths    = paths
      @terminal = terminal
      @launcher = launcher || Launcher.new(paths: paths)
      @clock    = clock
    end

    def run
      options = parse_options
      return options[:status] if options.key?(:status)

      unless File.directory?(@paths.projects)
        @terminal.write_error("No Claude projects directory at #{@paths.projects}\n")
        return FAILURE
      end

      sessions = load_sessions(options[:project])
      return list(sessions) if options[:list]

      browse(sessions, trash: options[:trash])
    end

    private

    def load_sessions(project)
      sessions = SessionLoader.new(paths: @paths, clock: @clock).load_all
      return sessions unless project

      needle = project.downcase
      sessions.select { |session| "#{session.project} #{session.cwd}".downcase.include?(needle) }
    end

    def list(sessions)
      sessions.each { |session| @terminal.write("#{session.to_line(@clock.now)}\n") }
      SUCCESS
    end

    def browse(sessions, trash:)
      browser = Browser.new(sessions, terminal: @terminal, paths: @paths,
                                      launcher: @launcher, trash: trash, clock: @clock)
      session = browser.run
      return SUCCESS if session.nil?

      resume(session)
    end

    # The browser has already torn down the alternate screen, so this banner
    # lands in the user's scrollback right before claude takes over.
    def resume(session)
      @terminal.write("Resuming #{Ansi::BOLD}#{session.title}#{Ansi::RESET}\n")
      @terminal.write("#{Ansi::DIM}#{session.working_dir} · #{@launcher.command_for(session)}#{Ansi::RESET}\n")
      @launcher.resume(session)
      SUCCESS
    rescue SystemCallError => e
      @terminal.write_error("Failed to launch claude: #{e.message}\n")
      FAILURE
    end

    def parse_options
      options = { trash: false, project: nil, list: false }
      parser  = build_parser(options)
      parser.parse(@argv)

      case options[:action]
      when :help    then finish(options, "#{parser}\n")
      when :version then finish(options, "claude-chats #{VERSION}\n")
      end
      options
    rescue OptionParser::ParseError => e
      @terminal.write_error("#{e.message}\nTry `claude-chats --help`.\n")
      { status: FAILURE }
    end

    def finish(options, message)
      @terminal.write(message)
      options[:status] = SUCCESS
    end

    def build_parser(options)
      OptionParser.new do |opts|
        opts.banner = 'Usage: claude-chats [options]'
        opts.separator ''
        opts.separator 'Browse Claude Code chats. Mark with d, delete marked with Enter, open one with o.'
        opts.separator ''
        opts.on('-t', '--trash', "Move chats to #{@paths.trash} instead of deleting them") do
          options[:trash] = true
        end
        opts.on('-p', '--project SUBSTR', 'Only chats whose project or directory matches SUBSTR') do |value|
          options[:project] = value
        end
        opts.on('-l', '--list', 'Print chats and exit') { options[:list] = true }
        opts.on('-v', '--version', 'Show version') { options[:action] = :version }
        opts.on('-h', '--help', 'Show this help') { options[:action] = :help }
      end
    end
  end
end
