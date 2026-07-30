# frozen_string_literal: true

module ClaudeChats
  # One chat transcript, described well enough to list, resume or delete.
  class Session
    MINUTE = 60
    HOUR   = 60 * 60
    DAY    = 24 * 60 * 60
    MONTH  = 30 * DAY

    KILOBYTE = 1024
    MEGABYTE = 1024 * 1024

    attr_reader :path, :id, :project_dir, :cwd, :title, :branch, :messages, :mtime, :bytes

    def initialize(path:, id:, project_dir:, title:, mtime:, bytes:,
                   messages: 0, cwd: nil, branch: nil, sidechain_only: false,
                   paths: Paths.new, clock: Time)
      @path           = path
      @id             = id
      @project_dir    = project_dir
      @title          = title
      @mtime          = mtime
      @bytes          = bytes
      @messages       = messages
      @cwd            = cwd
      @branch         = branch
      @sidechain_only = sidechain_only
      @paths          = paths
      @clock          = clock
    end

    def sidechain_only?
      @sidechain_only
    end

    def env_dir
      @paths.session_env_for(id)
    end

    def live?
      !id.nil? && id == @paths.live_session_id
    end

    # Short label for the list. Falls back to the encoded project directory when
    # the transcript never recorded a working directory.
    def project
      return File.basename(cwd) if cwd && !cwd.empty?

      File.basename(project_dir).sub(/\A-/, '').tr('-', '/')
    end

    # Where `claude --resume` should be launched. The directory encoded in the
    # project directory name is lossy — dashes inside real path segments become
    # slashes — so only trust either candidate if it exists on disk.
    def working_dir
      return cwd if cwd && Dir.exist?(cwd)

      decoded = File.basename(project_dir).tr('-', '/')
      decoded if Dir.exist?(decoded)
    end

    def age(now = @clock.now)
      seconds = now - mtime
      case seconds
      when ...MINUTE     then "#{seconds.to_i}s ago"
      when MINUTE...HOUR then "#{(seconds / MINUTE).to_i}m ago"
      when HOUR...DAY    then "#{(seconds / HOUR).to_i}h ago"
      when DAY...MONTH   then "#{(seconds / DAY).to_i}d ago"
      else mtime.strftime('%Y-%m-%d')
      end
    end

    def size
      case bytes
      when ...KILOBYTE          then "#{bytes}B"
      when KILOBYTE...MEGABYTE  then format('%.0fK', bytes / KILOBYTE.to_f)
      else                           format('%.1fM', bytes / MEGABYTE.to_f)
      end
    end

    LINE_FORMAT = '%<age>-9s  %<project>-18.18s  %<messages>4d msg  %<size>6s  %<title>s'

    def to_line(now = @clock.now)
      format(LINE_FORMAT, age: age(now), project: project, messages: messages, size: size, title: title)
    end

    def matches?(query)
      return true if query.nil? || query.empty?

      needle = query.downcase
      [title, project, cwd, id].compact.any? { |field| field.downcase.include?(needle) }
    end
  end
end
