# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `make install` puts `claude-chats` on your PATH without going through RubyGems, so one install works
  under every Ruby on the machine instead of only the one whose gem home received it. `make uninstall`,
  `make reinstall` and `PREFIX=` are there too.

## [0.2.0] - 2026-08-06

### Added

- <kbd>p</kbd> opens a preview beside the list, showing the last few turns of the highlighted chat so
  two similarly named chats can be told apart before deleting one. Closed by default, and unavailable
  on terminals too narrow to hold both. Tool calls and their results are skipped, and only the
  highlighted chat's transcript is read — from the end, so a megabyte-long chat costs no more than a
  short one.

### Fixed

- A transcript containing an invalid UTF-8 byte no longer takes down the whole listing.

## [0.1.0] - 2026-07-30

First release.

### Added

- Full-screen list of Claude Code chats, newest first, showing title, project, age, message count and size.
- Mark chats with <kbd>d</kbd> and delete them with <kbd>Enter</kbd>, behind a typed `yes` confirmation.
  Deleting also removes the chat's orphaned `session-env/<session-id>` directory.
- `--trash` to move chats to `~/.claude/trash/<timestamp>-<session-id>/` instead of deleting them.
- <kbd>o</kbd> to open a chat with `claude --resume` from its original working directory, with up-front checks
  for a missing `claude`, a chat with no messages, a directory that no longer exists, and the chat the process
  is itself running in.
- Filtering with <kbd>/</kbd> over title, project, directory and session id.
- `--list`, `--project`, `--version` and `--help`.
- Honours `CLAUDE_CONFIG_DIR`.

[Unreleased]: https://github.com/miladbeigi/claude-chats/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/miladbeigi/claude-chats/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/miladbeigi/claude-chats/releases/tag/v0.1.0
