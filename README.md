# claude-chats

[![CI](https://github.com/miladbeigi/claude-chats/actions/workflows/ci.yml/badge.svg)](https://github.com/miladbeigi/claude-chats/actions/workflows/ci.yml)

Browse, resume and delete [Claude Code](https://claude.com/claude-code) chats from your terminal.

Claude Code keeps every conversation as a JSON transcript under `~/.claude/projects/`, but offers no way to
clean them up — there is no "delete this chat" command. This is that missing command, plus a fast way to find
an old conversation and jump back into it.

```
Claude Code chats  5 chats  2 marked
   the vault raft rollout keeps flaking on the se…     1m ago  infra                 41 msg     8K
 ✗ why does the deploy hang on migrate?               25m ago  api                  321 msg    45K
 ● add pagination to the members list                  1h ago  web                   13 msg     4K
 ✗ /exit                                               1d ago  web                    1 msg   145B
   rename the billing webhook handler                  3d ago  api                  128 msg    21K
j/k move · o open · p preview · d mark · D all · u none · / filter · Enter delete marked · q quit
```

`✗` is marked for deletion, `●` is the chat you are currently running in.

When a title is not enough to tell you what a chat was — `reorganize-repo-structure` and
`reorganize-repo-structure-github` look much the same — press <kbd>p</kbd> for the last few things it
actually said:

```
Claude Code chats  5 chats  2 marked                            │ infra · 1m ago · 41 msg
                                                                │
   the vault raft rollout …     1m ago  infra           41 msg  │ claude  autopilot still reported
 ✗ why does the deploy han…    25m ago  api            321 msg  │         the old peer, so it needs
 ● add pagination to the m…     1h ago  web             13 msg  │         a list-peers check
 ✗ /exit                        1d ago  web              1 msg  │         between evictions
   rename the billing webh…     3d ago  api            128 msg  │    you  add that to the runbook
                                                                │ claude  done — the peer check now
                                                                │         runs before every
                                                                │         eviction

j/k move · o open · p preview · d mark · D all · u none · / filter · Enter delete marked · q quit
```

The pane follows the cursor, and <kbd>p</kbd> again closes it. Its columns come out of the list, so
while it is open the titles are shorter and the size column steps aside.

## Install

Requires Ruby 3.1 or newer. No gem dependencies — the standard library is all it uses.

The repository ships with a `mise.toml` that pins Ruby 3.4. If you use
[mise](https://mise.jdx.dev), it will automatically activate the right Ruby version:

```sh
mise install   # install Ruby 3.4 (first time only)
```

Then install the gem:

```sh
git clone https://github.com/miladbeigi/claude-chats.git
cd claude-chats
mise install        # install pinned Ruby (skip if already done)
rake install
```

That installs the `claude-chats` command. To remove it: `gem uninstall claude-chats`.

## Usage

```sh
claude-chats
```

| Key | Action |
| --- | --- |
| <kbd>↑</kbd>/<kbd>↓</kbd> or <kbd>j</kbd>/<kbd>k</kbd> | Move |
| <kbd>PgUp</kbd>/<kbd>PgDn</kbd>, <kbd>g</kbd>/<kbd>G</kbd> | Page, jump to top/bottom |
| <kbd>o</kbd> | Open the chat with `claude --resume`, in its original directory |
| <kbd>p</kbd> | Open or close the preview of the highlighted chat |
| <kbd>d</kbd> or <kbd>Space</kbd> | Mark / unmark for deletion |
| <kbd>D</kbd> / <kbd>u</kbd> | Mark everything visible / clear all marks |
| <kbd>/</kbd> | Filter by title, project, directory or session id |
| <kbd>Esc</kbd> | Clear the filter, then the marks |
| <kbd>Enter</kbd> | Delete everything marked, after a confirmation |
| <kbd>q</kbd> | Quit |

### Flags

| Flag | Meaning |
| --- | --- |
| `-t`, `--trash` | Move chats to `~/.claude/trash/` instead of deleting them |
| `-p`, `--project SUBSTR` | Only chats whose project or directory matches `SUBSTR` |
| `-l`, `--list` | Print the chats and exit — handy in pipes |
| `-v`, `--version` | Print the version |
| `-h`, `--help` | Show help |

Deleting asks you to type `yes` in full; anything else cancels. Nothing is removed until you confirm, and a
single keystroke can never delete a chat.

## What deletion actually removes

For each chat you confirm:

- its transcript, `~/.claude/projects/<encoded-directory>/<session-id>.jsonl`
- its scratch directory, `~/.claude/session-env/<session-id>`, which Claude Code otherwise leaves orphaned

**Plain `Enter` deletes for real and cannot be undone.** Use `--trash` if you would rather move chats to
`~/.claude/trash/<timestamp>-<session-id>/` and clean up later.

Nothing stops you from deleting the chat you are currently sitting in — it is marked `●` for that reason. The
running Claude Code process keeps writing to the deleted file, so the chat reappears on its next write. Quit
that session first if you want it gone.

## Notes

Set `CLAUDE_CONFIG_DIR` to point at a different Claude home; everything follows it.

Titles come from whatever is most useful: the name you gave the chat with `/rename`, otherwise the generated
title, otherwise your first message, otherwise the slash command you ran. Wrapper records that Claude Code
writes around slash commands and hook output are not counted as messages, so a chat where you only typed
`/exit` shows up as exactly that — usually the first thing worth deleting.

The preview shows the last few turns that carried text. Most of a working chat is tool calls and their
results, which have nothing to read, so they are skipped — and because a long run of them can fill the
end of a file, the preview reads back from the end of the transcript until it finds enough to show. It
reads only the highlighted chat, and only while the pane is open, so moving through a list of large
transcripts stays quick. Below about 80 columns there is no room for both, and <kbd>p</kbd> does
nothing.

### Compatibility

This reads Claude Code's on-disk files directly. That layout is not a documented or supported API, so a
future release could change it and break this tool. Everything is defensive — unknown record types are
ignored and unparseable lines skipped — but treat it as best-effort. Built and tested against Claude Code
**2.1.220**.

## Development

```sh
mise install            # activate the pinned Ruby
bundle install
bundle exec rake        # tests and RuboCop
bundle exec rake test
```

The suite never touches your real `~/.claude`: fixtures are synthetic transcripts written to a temporary
directory, and the test base class refuses to run if its paths resolve inside your real Claude home. The
terminal is faked so the UI can be driven deterministically without a pty; one integration test does drive
the real executable through a pty, and deliberately cancels at the confirmation prompt.

## License

[MIT](LICENSE).

Not affiliated with, authorised by, or endorsed by Anthropic. "Claude" is a trademark of Anthropic.
