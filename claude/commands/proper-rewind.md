List the recent agent-turn snapshots by running
`git log --oneline -25 --grep='^wip('`, show them to me with a short
description of what each turn appears to have changed (`git show --stat` on
a few if helpful), and ask me which one to restore. When I choose:

1. `git add -A` and, if anything is dirty, commit it as
   `wip(claude): pre-rewind safety snapshot` (use --no-verify).
2. `git update-ref refs/cursor-backups/$(date +%s) HEAD`
3. `git reset --hard <chosen sha>`

This restores the ENTIRE workspace to that turn, including files created,
deleted, or modified by bash commands — which the built-in /rewind cannot
revert. Do not use `git revert`. The hard reset is intentional and safe:
every prior state is committed and the backup ref preserves what we discard.
Note this rewinds files only, not the conversation — if I also want the
conversation rewound, tell me to use Esc Esc (the built-in rewind) instead,
and the git side will sync automatically on my next message.
