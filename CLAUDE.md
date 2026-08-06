# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A zero-dependency Ruby gem (`claude-chats`) providing a terminal UI over the chat transcripts Claude
Code leaves in `~/.claude/projects/`: list them newest first, filter, resume one with
`claude --resume`, or mark several and delete them. Ruby >= 3.1, standard library only — **do not add
runtime gem dependencies**; the "only stdlib" property is a deliberate feature (see `PLANNING.md`).

## Commands

```sh
bundle install
bundle exec rake                 # tests + RuboCop (the default task)
bundle exec rake test
bundle exec rubocop
rake install                     # installs the `claude-chats` executable
```

Single file or single test — `rake test` has no file filter, so invoke Minitest directly:

```sh
bundle exec ruby -Ilib -Itest test/browser_test.rb
bundle exec ruby -Ilib -Itest test/session_test.rb -n /age/
```

CI runs `rake test` on Ruby 3.1–3.4 × ubuntu/macOS, `rubocop` on 3.4, and a third job that proves
`rake install` works from a bare checkout and that `--list` handles both an empty and a missing
Claude home (the missing case must exit non-zero).

## Architecture

Dependencies point one way: `CLI` → `Browser` → `Terminal`/`Launcher`/`Preview`, with `Paths`,
`Session`, `Records` and `Ansi` as leaves. Two design rules make the whole thing testable in-process:

- **Nothing reads global state directly.** `Paths` resolves `CLAUDE_CONFIG_DIR`,
  `CLAUDE_CODE_SESSION_ID` and `PATH` from an injected `env` hash, not `ENV` at load time. `Time` is
  injected as `clock:` everywhere a duration or timestamp is rendered. Every class takes
  `paths:`/`clock:`/`terminal:`/`launcher:` keywords with real defaults. Keep new code on this
  pattern — a test that reaches the real `~/.claude` is a hard failure (`TestCase#refute_real_home`).
- **`CLI#run` returns an exit status** instead of calling `exit` (only `exe/claude-chats` exits), and
  `Browser#run` *returns* the session to resume rather than launching it. Only `Launcher#resume`
  replaces the process, so the browser can be driven end-to-end without a pty.

Roles:

- `lib/claude_chats/paths.rb` — the single place that knows Claude Code's on-disk layout
  (`projects/`, `session-env/`, `trash/`).
- `records.rb` — what a transcript record *is*: the noise patterns, text extraction, and the scrub
  that keeps one bad byte from taking down a listing. Both readers go through it, so the format is
  understood in one place.
- `session_loader.rb` — one pass over each `*.jsonl` transcript pulling out only what the list needs.
  Title precedence is `custom-title` → `ai-title` → first human message → slash command name →
  `(empty chat)`. Slash-command/hook wrapper records (`NOISE`) are excluded from the message count,
  which is why a `/exit`-only chat shows 1 msg.
- `session.rb` — value object; formats age/size/line, and resolves `working_dir` (prefers the
  recorded `cwd`, falls back to decoding the project directory name, and only trusts either if it
  exists on disk — the dash-to-slash decoding is lossy).
- `terminal.rb` — the only file touching `IO.console`, raw-mode reads and escape-sequence decoding.
  `Browser` speaks solely to this interface, which is what `FakeTerminal` replaces.
- `browser.rb` — the full-screen list: key dispatch table (`ACTIONS`), scrolling, rendering,
  confirmation and deletion. It sets the `Metrics/ClassLength` limit, which is why the pane lives
  next door rather than inside it.
- `preview_loader.rb` / `preview.rb` — the right-hand pane, opened with `p` and closed by default.
  The loader *seeks to the end* of one transcript rather than scanning it, widening the window when a
  tail of tool calls holds no prose; the renderer wraps turns into a fixed number of lines and
  composes them beside the list. Nothing is read until the pane is open, and then only the
  highlighted row — which is what keeps a per-keystroke read affordable.
- `launcher.rb` — finds `claude` by walking `PATH` (via `Paths`), then `Dir.chdir` + `exec`.

### Invariants worth preserving

- **No single keystroke deletes anything.** Marks are collected, then `Enter` shows a confirmation
  screen requiring the literal word `yes`; anything else cancels.
- **Deleting a chat also removes its `session-env/<session-id>` scratch directory** (`--trash` moves
  both into `trash/<timestamp>-<session-id>/`).
- **The live session is never resumable.** `Session#live?` compares against
  `CLAUDE_CODE_SESSION_ID`; it renders as `●` and `Browser#resume_blocker` refuses it. All resume
  blockers are checked up front and surface as a status line, never a dead shell.
- **`Terminal#restore` runs in an `ensure`,** so an exception cannot leave the user in the alternate
  screen or raw mode.
- **`Esc` never touches the preview pane.** It backs out of the filter, then the marks; only `p`
  toggles the pane. Losing the pane on the way to clearing a filter is a surprise.
- **The pane comes out of the width budget, never on top of it,** and occupies the rows the list
  already has, so it cannot change how tall or wide the screen is.
- **Rendered lines never reach the terminal width** (they would soft-wrap and shift the layout);
  width is `@terminal.width - 1`, clamped. Truncating a line that carries colour codes appends a
  reset so a severed sequence cannot colour the rest of the screen.
- **The transcript format is not a documented API.** Stay defensive: unparseable JSON lines and
  unknown record types are skipped, `File.stat` failures drop the session, never raise. Note the
  Claude Code version tested against in the README when behaviour depends on the format.

## Tests

`test/test_helper.rb` gives every test its own throwaway Claude home via `Dir.mktmpdir` plus a
`TranscriptBuilder` that writes synthetic transcripts — use its record helpers (`user`, `assistant`,
`ai_title`, `caveat`, `slash_command`, `session_env`, …) rather than hand-rolling JSON. `FakeTerminal`
drives the UI from a scripted key queue (`keys:`) and prompt answers (`answers:`), and exposes
`frames`/`last_frame_lines` with escapes stripped; running out of keys reads as `q`. No sleeps, no
pty — except `integration_test.rb`, which drives the real `exe/claude-chats` through a PTY to cover
`IO.console` for real and deliberately cancels at the confirmation prompt.

## Conventions

- `# frozen_string_literal: true` at the top of every file; build up mutable strings with `+''`.
- RuboCop is configured, not disabled: `.rubocop.yml` raises metrics to what the code needs and
  pins `NewCops: disable`. Prefer restructuring over inline `rubocop:disable`.
- Every class carries a short comment explaining *why* it exists and what it deliberately does not
  do. Match that density — comments here justify decisions rather than narrate code.
- User-facing changes go in `CHANGELOG.md` under `[Unreleased]` (Keep a Changelog format), and the
  version lives in `lib/claude_chats/version.rb`.
- `PLANNING.md` is a local-only scratchpad of verified issues and next steps, excluded via
  `.git/info/exclude` — check it before designing something new, and don't commit it.
