# Ship: turn WIP snapshots into clean, reviewable commits

The branch history contains many `wip(cursor)` snapshot commits (automatic
per-turn journal). Convert everything since the last real commit into a small
number of well-crafted commits.

1. Find the base: the most recent commit whose message does NOT start with
   `wip(cursor)` (inspect `git log --format='%h %s' -50`). If I named a base
   or branch in my message, use that instead.
2. Preserve the journal first:
   `git update-ref refs/cursor-backups/$(date +%s)-preship HEAD`
3. Show me the net change (`git diff --stat <base> HEAD`) and propose a
   logical grouping into 1–4 commits (by feature/concern, not by file type),
   with a draft message for each. Wait for my approval.
4. On approval: `git reset --soft <base>`, then for each group stage its
   files (`git add <paths>`) and commit with the agreed message. Real commits
   here — do NOT use `--no-verify`; if pre-commit hooks fail, fix and retry.
   Fold the `.cursor-turn` marker file into the last group without comment.
5. Show the final `git log --oneline <base>..HEAD`.

Never push unless I explicitly say so. Do not use `git rebase -i`.
