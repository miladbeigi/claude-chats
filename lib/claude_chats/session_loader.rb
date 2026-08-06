# frozen_string_literal: true

module ClaudeChats
  # Reads the minimum out of each transcript needed to describe it in a list.
  #
  # The on-disk format is a JSON-per-line log that Claude Code does not document
  # as an API, so everything here is defensive: unknown record types are ignored
  # and unparseable lines are skipped rather than fatal. What counts as a message
  # lives in Records, shared with the preview.
  class SessionLoader
    NO_MESSAGES = '(empty chat)'

    def initialize(paths: Paths.new, clock: Time)
      @paths = paths
      @clock = clock
    end

    def load_all
      Dir.glob(File.join(@paths.projects, '*', '*.jsonl'))
         .filter_map { |path| parse(path) }
         .sort_by { |session| -session.mtime.to_f }
    end

    def parse(path)
      found = scan(path)
      stat  = File.stat(path)

      Session.new(
        path: path,
        id: File.basename(path, '.jsonl'),
        project_dir: File.dirname(path),
        cwd: found[:cwd],
        title: title_for(found),
        branch: found[:branch],
        messages: found[:messages],
        mtime: stat.mtime,
        bytes: stat.size,
        sidechain_only: !found[:main_chat],
        paths: @paths,
        clock: @clock
      )
    rescue SystemCallError
      nil
    end

    private

    def scan(path)
      found = { messages: 0, main_chat: false }

      File.foreach(path) do |line|
        record = parse_line(line)
        next unless record

        case record['type']
        when 'custom-title' then found[:custom_title] ||= record['customTitle']
        when 'ai-title'     then found[:ai_title]     ||= record['aiTitle']
        when 'user', 'assistant' then absorb_message(found, record)
        end
      end

      found
    end

    def absorb_message(found, record)
      return if record['isSidechain']

      found[:main_chat] = true
      found[:cwd]    ||= record['cwd']
      found[:branch] ||= record['gitBranch']

      text = normalise(Records.extract_text(record.dig('message', 'content')))
      return if text.empty? || text.match?(Records::NOISE)

      command = text.match(Records::COMMAND_NAME)
      found[:command] ||= command[1] if command
      found[:messages] += 1
      return unless record['type'] == 'user' && record.dig('origin', 'kind') == 'human'

      found[:first_prompt] ||= text
    end

    # A chat is best identified by what the user renamed it to, then by the
    # generated title, then by whatever they actually said first.
    def title_for(found)
      title = found[:custom_title] || found[:ai_title] || found[:first_prompt] ||
              found[:command] || NO_MESSAGES
      normalise(title)
    end

    def parse_line(line)
      Records.parse_line(line)
    end

    def normalise(text)
      Records.normalise(text)
    end
  end
end
