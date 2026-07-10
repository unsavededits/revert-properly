# How it works

## What the built-in systems actually track

Both Cursor checkpoints and Claude Code rewind snapshot only the files the
agent modifies **through its file-editing tool**, and restore only those.
This is documented:

- Claude Code: "File checkpointing tracks file modifications made through
  the Write, Edit, and NotebookEdit tools… Checkpointing does not track
  files modified by bash commands."
  ([docs](https://code.claude.com/docs/en/checkpointing))
- Cursor: checkpoints "track only Agent changes (not manual edits)"; Cursor
  staff direct users to `git revert`/`git reset` to undo agent-made commits
  ([docs](https://cursor.com/docs/agent/chat/checkpoints)).

Empirically (Cursor 3.10.20): restoring a checkpoint reverts edit-tool
files — including, notably, bash-*deletions* of files the agent had
previously edit-tool-touched in the session — but leaves bash-*created*
files and other terminal side effects in place, and fires no hook or event.
The conversation transcript on disk is append-only: a restore leaves zero
trace in it, and hook payloads carry no restore-position field. **There is
no programmatic signal that a restore happened.** Everything below follows
from that constraint.

## The journal

A `stop`/`Stop` hook commits the whole workspace after every agent turn
that changed anything. A `beforeSubmitPrompt`/`UserPromptSubmit` hook
commits any user edits *before* a turn starts (otherwise a file you just
created could be bash-deleted mid-turn without ever having been committed —
genuinely unrecoverable). Every state the workspace has ever been in is
therefore a commit.

## Restore detection (the fingerprint)

Since no event fires on restore, detection is forensics at the user's next
message:

1. List files that differ from HEAD (the last snapshot) — tracked or
   untracked, using blob hashes for exact comparison.
2. If **every** dirty file byte-for-byte matches its state in some older
   `wip(` snapshot, that combination is essentially impossible to produce
   by accident: the tool just rewrote a set of files to precisely an old
   state. That's the restore-button's signature. Reset to the newest
   matching snapshot (after committing the current mixed state and
   preserving it under `refs/cursor-backups/`).
3. If the dirty files match no snapshot, they're the user's own edits —
   commit them as a pre-turn snapshot and do nothing else. Manual edits can
   never trigger a reset.

## The turn nonce

The fingerprint channel is only the edit-tool files — a lossy projection of
"which turn". Two failure classes follow: a reverted turn containing *only*
bash changes gives the button nothing to rewrite (invisible restore), and
files whose content repeats across turns can make the newest-match land a
turn or two late (ambiguity).

Fix: an always-on rule instructs the agent to bump a counter file
(`.cursor-turn` / `.claude-turn`) **via its edit tool** before its first
file modification in a turn. That plants a unique, checkpoint-tracked value
in every file-changing turn, so the button always has something to rewrite
and no two turns can be confused. The nonce **must** be written by the
agent's edit tool: hook- or bash-written files aren't checkpoint-tracked,
so the button would never revert them and they'd carry zero signal — this
was verified, not assumed. Compliance is model-followed; a skipped bump
degrades gracefully to the bare heuristic.

## Guard rails

- **Merge/rebase guard**: no commits or resets while `MERGE_HEAD`,
  `rebase-merge`, etc. exist — a mid-conflict `git add -A && git commit`
  would complete the merge with conflict markers.
- **Bloat protection**: common dependency/build dirs are seeded into
  `.git/info/exclude` (repo-local, affects untracked files only); a flood
  guard auto-excludes any top-level directory contributing >200 untracked
  files when a turn produces >300 changed paths. Note `git status`'s
  default directory-collapsing would defeat the count — the guard uses
  `-uall`.
- **Fail open**: every script exits 0 on any error. Worst case is a missed
  snapshot or missed sync, never a blocked prompt or destroyed state.
- **Never lossy**: anything a reset would discard is committed first and
  pinned under `refs/cursor-backups/` (reflog-independent, local-only,
  reclaimable via `/git-prune`).

## Known limits

1. If the agent skipped the nonce AND the reverted turns were bash-only,
   the restore is undetectable (tree is byte-identical to HEAD). Files stay
   put while the conversation rewinds; fix manually with `/rewind`
   (`/git-rewind`). Nothing is lost.
2. Without a nonce, repeated file content across turns can sync to a
   slightly-too-new snapshot. Recoverable via `refs/cursor-backups/`.
3. The sync happens at your next message — between the button click and
   that message, the tree is in the tool's half-restored state.
4. Hand-editing files between clicking restore and sending your next
   message mixes user edits into the fingerprint; the strict all-files-must-
   match rule then stands down (safe, but no auto-sync).
