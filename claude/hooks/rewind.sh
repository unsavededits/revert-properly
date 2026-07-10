#!/bin/bash
# Rewind the workspace to a previous agent-turn snapshot (or any commit).
#
#   rewind.sh            list recent turn snapshots
#   rewind.sh <sha>      hard-reset the workspace to that snapshot
#
# A hard reset here is safe-by-construction: every prior state is itself a
# commit, and even "lost" resets are recoverable via `git reflog` for ~90 days.

if [ -z "$1" ]; then
  echo "Recent agent-turn snapshots (newest first):"
  git log --oneline -25 --grep='^wip('
  echo
  echo "Usage: rewind.sh <sha>   — restores the ENTIRE workspace to that turn,"
  echo "including files created/deleted/modified by terminal commands."
  exit 0
fi

git add -A                      # snapshot any uncommitted state first,
if [ -n "$(git status --porcelain)" ]; then
  git commit -q --no-verify -m "wip(cursor): pre-rewind safety snapshot"
fi
git reset --hard "$1"
echo "Workspace restored to $1. (Undo the rewind itself with: git reflog)"
