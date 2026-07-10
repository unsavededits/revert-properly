#!/usr/bin/env python3
"""Cursor `beforeSubmitPrompt` hook: make git follow the checkpoint button.

Cursor's checkpoint-restore button rewinds the conversation and reverts
edit-tool file changes, but leaves terminal-command artifacts behind and
fires no hook. This script runs when the user sends their next message:
if the working tree's changes vs HEAD exactly match an older turn snapshot
(the fingerprint of a checkpoint restore), it hard-resets git to that
snapshot so terminal artifacts revert too. The pre-reset state is committed
and kept under refs/cursor-backups/ first, so this is never lossy.

Always allows the prompt through, whatever happens.
"""
import json
import os
import subprocess
import sys
import time


def allow():
    print(json.dumps({"continue": True}))
    sys.exit(0)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    roots = data.get("workspace_roots") or []
    if roots and os.path.isdir(roots[0]):
        os.chdir(roots[0])

    if os.path.exists(".cursor-git-safety-off"):
        allow()  # per-repo kill switch
    if git("rev-parse", "--is-inside-work-tree").returncode != 0:
        allow()

    gitdir = git("rev-parse", "--git-dir").stdout.strip()
    for op in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
               "rebase-merge", "rebase-apply"):
        if os.path.exists(os.path.join(gitdir, op)):
            allow()  # never commit/reset mid merge/rebase/etc.

    # Log the raw payload for restore-signal research (see auto-commit.sh).
    try:
        gitdir = git("rev-parse", "--git-dir").stdout.strip()
        with open(os.path.join(gitdir, "cursor-git-safety-payloads.jsonl"),
                  "a") as f:
            f.write(json.dumps(data) + "\n")
    except Exception:
        pass

    # Files that differ from the last snapshot (HEAD), tracked or untracked.
    st = git("status", "--porcelain=v1", "-z").stdout
    entries = st.split("\0")
    dirty = []
    i = 0
    while i < len(entries):
        e = entries[i]
        if not e:
            i += 1
            continue
        code, path = e[:2], e[3:]
        dirty.append(path)
        if code[0] == "R":  # rename entries carry the original path next
            i += 1
            if i < len(entries) and entries[i]:
                dirty.append(entries[i])
        i += 1
    if not dirty:
        allow()  # clean tree: no restore happened, nothing to do

    def worktree_blob(path):
        if not os.path.lexists(path):
            return None  # deleted in worktree
        r = git("hash-object", "--", path)
        return r.stdout.strip() if r.returncode == 0 else ""

    def commit_blob(commit, path):
        r = git("rev-parse", f"{commit}:{path}")
        return r.stdout.strip() if r.returncode == 0 else None

    current = {p: worktree_blob(p) for p in dirty}

    head = git("rev-parse", "HEAD").stdout.strip()
    # Match snapshots from ANY agent kit (wip(cursor), wip(claude), ...) so
    # both tools can share one repo's journal.
    log = git("log", "--format=%H", "-50", "--grep=^wip(").stdout.split()
    candidates = [c for c in log if c != head]

    # A restore's fingerprint: EVERY dirty file exactly matches some older
    # snapshot. Manual edits produce content matching no snapshot -> no match
    # -> we deliberately do nothing.
    target = None
    for c in candidates:
        if all(commit_blob(c, p) == blob for p, blob in current.items()):
            target = c
            break
    if not target:
        # Dirty but matching no snapshot: these are the user's own edits.
        # Commit them so the turn starts from a recorded state — otherwise a
        # file the user just created could be bash-deleted mid-turn and folded
        # invisibly into the end-of-turn snapshot, never having been committed.
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m",
            "wip(cursor): pre-turn snapshot (user edits)")
        allow()

    # Detected a checkpoint restore. Preserve the current mixed state, keep a
    # findable ref to it, then align the whole tree to the restored turn.
    git("add", "-A")
    git("commit", "-q", "--no-verify", "-m",
        "wip(cursor): pre-sync state (before aligning to checkpoint restore)")
    git("update-ref", f"refs/cursor-backups/{int(time.time())}", "HEAD")
    git("reset", "--hard", target)
    allow()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        allow()  # never block the user's prompt
