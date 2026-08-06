# frozen_string_literal: true

module ClaudeChats
  # Writes synthetic transcripts that mirror Claude Code's on-disk format, so
  # tests never read or write the real ~/.claude.
  class TranscriptBuilder
    DEFAULT_PROJECT = '-tmp-demo'
    DEFAULT_CWD     = '/tmp/demo'

    def initialize(paths)
      @paths = paths
    end

    # Writes a transcript file and returns its path.
    def write(id:, records:, project: DEFAULT_PROJECT, mtime: nil)
      write_lines(id: id, lines: records.map { |record| JSON.generate(record) },
                  project: project, mtime: mtime)
    end

    # Verbatim lines, for malformed JSON and half-written records.
    def write_lines(id:, lines:, project: DEFAULT_PROJECT, mtime: nil)
      dir = File.join(@paths.projects, project)
      FileUtils.mkdir_p(dir)
      file = File.join(dir, "#{id}.jsonl")
      File.write(file, lines.map { |line| "#{line}\n" }.join)
      File.utime(mtime, mtime, file) if mtime
      file
    end

    # A plain two-message chat — the common case for list and delete tests.
    def chat(id:, text: 'hello there', project: DEFAULT_PROJECT, cwd: DEFAULT_CWD, mtime: nil, extra: [])
      write(
        id: id,
        project: project,
        mtime: mtime,
        records: [user(text, cwd: cwd), assistant('sure', cwd: cwd), *extra]
      )
    end

    def user(text, cwd: DEFAULT_CWD, human: true, sidechain: false, branch: 'main')
      record = {
        'type' => 'user',
        'isSidechain' => sidechain,
        'message' => { 'role' => 'user', 'content' => text },
        'cwd' => cwd,
        'gitBranch' => branch
      }
      record['origin'] = { 'kind' => 'human' } if human
      record
    end

    def assistant(text, cwd: DEFAULT_CWD, sidechain: false)
      {
        'type' => 'assistant',
        'isSidechain' => sidechain,
        'message' => { 'role' => 'assistant', 'content' => [{ 'type' => 'text', 'text' => text }] },
        'cwd' => cwd
      }
    end

    # Most of a real agentic chat is these two: content parts with no text, so
    # nothing a preview can show.
    def tool_use(name = 'Bash', cwd: DEFAULT_CWD)
      {
        'type' => 'assistant',
        'isSidechain' => false,
        'cwd' => cwd,
        'message' => { 'role' => 'assistant',
                       'content' => [{ 'type' => 'tool_use', 'name' => name, 'input' => { 'command' => 'ls' } }] }
      }
    end

    def tool_result(text = 'ok')
      {
        'type' => 'user',
        'isSidechain' => false,
        'cwd' => DEFAULT_CWD,
        'message' => { 'role' => 'user', 'content' => [{ 'type' => 'tool_result', 'content' => text }] }
      }
    end

    def ai_title(title)
      { 'type' => 'ai-title', 'aiTitle' => title }
    end

    def custom_title(title)
      { 'type' => 'custom-title', 'customTitle' => title }
    end

    def caveat
      user('<local-command-caveat>Caveat: the messages below were generated ' \
           'while running local commands.</local-command-caveat>', human: false)
    end

    def slash_command(name)
      user("<command-name>#{name}</command-name> <command-message>#{name.delete_prefix('/')}" \
           '</command-message> <command-args></command-args>', human: false)
    end

    def command_output(text)
      user("<local-command-stdout>#{text}</local-command-stdout>", human: false)
    end

    # The per-session scratch directory Claude Code leaves next to a transcript.
    def session_env(id)
      dir = File.join(@paths.session_env, id)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'env'), "EXAMPLE=1\n")
      dir
    end
  end
end
