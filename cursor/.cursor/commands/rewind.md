# Rewind to a previous agent turn

Run `bash .cursor/hooks/rewind.sh` in the terminal to list recent turn
snapshots (commits prefixed `wip(cursor)`), show me the list with a short
description of what each turn appears to have changed (`git show --stat` on a
few if helpful), and ask me which one to restore. When I choose, run
`bash .cursor/hooks/rewind.sh <sha>`.

Do not use `git revert`. Do not restore Cursor checkpoints from the chat UI.
The script performs a hard reset, which is intentional and safe here: every
prior state is committed, and the script takes a safety snapshot first.
