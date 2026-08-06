# frozen_string_literal: true

module ClaudeChats
  # Decoding rules for the transcript format, shared by everything that reads it.
  #
  # The format is a JSON-per-line log Claude Code does not document as an API, so
  # these live in one place: two readers guessing separately at what counts as a
  # message is how they drift apart.
  module Records
    # Wrapper records the CLI writes around slash commands and hook output. Real
    # conversation, from a human's point of view, they are not.
    NOISE = /\A<(local-command-caveat|local-command-stdout|local-command-stderr|system-reminder)/
    COMMAND_NAME = %r{<command-name>(/?[^<]+)</command-name>}

    # Message text is user-supplied and written straight to the screen. Pasted
    # terminal output really does carry escape sequences — transcripts here hold
    # hook stdout containing an OSC notify sequence — and a stray one moves the
    # cursor or recolours the UI, which truncating a line does not fix.
    CSI     = /\e\[[0-9;?]*[A-Za-z]/       # colours, cursor movement
    OSC     = /\e\][^\a\e]*(?:\a|\e\\)?/   # window title, notifications
    CONTROL = /[\x00-\x08\x0b-\x1f\x7f]/   # whatever is left (\e included), tab and newline aside

    module_function

    # Scrubbed here so nothing downstream has to be: a transcript with one bad
    # byte in it used to take the whole listing down from #normalise.
    def parse_line(line)
      record = JSON.parse(line.to_s.scrub)
      record.is_a?(Hash) ? record : nil
    rescue JSON::ParserError
      nil
    end

    def extract_text(content)
      case content
      when String then content
      when Array
        content.filter_map { |part| part['text'] if part.is_a?(Hash) && part['type'] == 'text' }.join(' ')
      end
    end

    def normalise(text)
      text.to_s.gsub(/\s+/, ' ').strip
    end

    # Run before #normalise, while any sequence is still intact.
    def sanitise(text)
      text.to_s.gsub(CSI, '').gsub(OSC, '').gsub(CONTROL, '')
    end
  end
end
