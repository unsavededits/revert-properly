# agent-git-safety

**Make Cursor's checkpoint button and Claude Code's rewind actually restore
everything — including the changes their built-in systems silently miss.**

## The problem

Cursor checkpoints and Claude Code rewind (Esc Esc, or the revert button in
the desktop app / VS Code extension) both share the same blind spot, and
it's documented, not a bug:

> "Checkpointing does not track files modified by bash commands."
> — [Claude Code docs](https://code.claude.com/docs/en/checkpointing)

> "Track only Agent changes (not manual edits)"
> — [Cursor docs](https://cursor.com/docs/agent/chat/checkpoints)

Both systems snapshot only files the agent edits **through its file-editing
tool**. Anything a terminal command does — `rm`, `sed`, code generators,
dependency installs, git operations — survives a "restore" untouched. If the
agent bash-deletes a file and you click revert, the file stays deleted. If it
generated artifacts you didn't want, they stay. Easy to verify yourself:
have the agent create a file via terminal, restore a checkpoint from before,
and watch the file survive.

## What this does

Small, dependency-free git hooks (bash + python3, no packages) for both
tools:

1. **Journal** — after every agent turn that changed anything, the entire
   workspace is committed (`wip(cursor)` / `wip(claude)` prefix). Turns that
   change nothing produce no commit. Your own between-turn edits are
   committed too, before the agent can touch them.
2. **Restore sync** — when you use the built-in checkpoint/rewind button,
   the next message you send triggers a detector: if the working tree's
   changes exactly match an older turn snapshot (the fingerprint of a
   restore), git hard-resets to that snapshot — so terminal-command changes
   revert along with everything else. The discarded state is preserved under
   `refs/cursor-backups/` first; nothing is ever lost.
3. **Turn nonce** — an always-on rule has the agent bump a `.cursor-turn` /
   `.claude-turn` counter via its edit tool at the start of any
   file-changing turn, so even bash-only turns leave a checkpoint-tracked
   fingerprint and detection is exact.
4. **Slash commands** — `/ship` (`/git-ship`): squash the journal into
   clean, logically-grouped commits before you push. `/rewind`
   (`/git-rewind`): file-only rewind keeping the conversation. `/git-prune`:
   reclaim disk from old backup refs.

You keep using your tool exactly as before. The revert button just becomes a
*complete* revert button.

## Install

Requires git and python3 (macOS/Linux).

**Cursor (global):** `bash install-cursor.sh`, then paste the contents of
`cursor/.cursor/rules/turn-marker.mdc` (below the frontmatter) into Cursor
Settings → Rules → User Rules, and Reload Window in open Cursor windows.
For a single project instead: copy `cursor/.cursor/` into the repo root.

**Claude Code (global):** `bash install-claude.sh`, effective in new
sessions. For a single project: copy `claude/hooks` scripts into
`.claude/hooks/`, register them in `.claude/settings.json` (Stop +
UserPromptSubmit), copy `claude/commands/*` to `.claude/commands/`, and
include `claude/GIT-SAFETY.md` from the project's CLAUDE.md.

**Per-repo opt-out:** `touch .cursor-git-safety-off` and/or
`.claude-git-safety-off` in any repo root.

## Using it on real/company codebases

Designed to be safe on mature repos, with two habits:

- **Work on a feature branch** (you already do). Snapshots land on the
  current branch and never leave your machine unless you push them.
- **Run `/ship` before pushing.** It squashes the journal into reviewable
  commits (and runs your pre-commit hooks, which snapshots deliberately
  skip). For belt-and-braces, `extras/pre-push-guard.sh` is a git pre-push
  hook that refuses to push `wip(` commits.

Built-in protections for the messy realities of big repos:

- **Merge/rebase guard**: the hooks never commit or reset while a merge,
  rebase, cherry-pick, or bisect is in progress (a mid-conflict `git commit`
  could complete the merge by accident).
- **Bloat protection**: common dependency/build directories are seeded into
  `.git/info/exclude` (repo-local, never committed, affects untracked files
  only — deliberately tracked paths keep being journaled), and a flood guard
  auto-excludes any directory that suddenly produces hundreds of untracked
  files (the `npm install` signature).
- **Housekeeping**: snapshots trigger a detached `git gc --auto`;
  `/git-prune` reclaims space from old backup refs.
- Detection scans only the last 50 snapshots — cost is independent of repo
  history. On very large working trees (100k+ files), enable git's
  fsmonitor (`git config core.fsmonitor true`) to keep `git status` fast.

## Caveats, honestly

- Snapshot commits use `git add -A` (your uncommitted edits ride along —
  that's the safety net working) and `--no-verify` (pre-commit hooks run on
  `/ship`'s real commits instead).
- The turn nonce is model-followed (rule injected every request). A skipped
  bump degrades to heuristic detection, which has two narrow edge cases
  (see [docs/how-it-works.md](docs/how-it-works.md)) — never breakage.
- Restore sync runs at your *next message*, not at the button click.
- The journal makes `git log` noisy until you `/ship`. That's the trade.
- Tested on macOS with Cursor 3.10 and Claude Code 2.1. Hook payload shapes
  may drift with tool updates; the scripts fail open (never block, never
  destroy) and log payloads to `.git/*-payloads.jsonl` for debugging.

## How it works

The detection trick, the empirical experiments behind it, and the failure
modes are written up in [docs/how-it-works.md](docs/how-it-works.md).

## License

MIT
