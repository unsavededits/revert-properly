#!/usr/bin/env python3
"""Claude Code `UserPromptSubmit` hook: make git follow /rewind (Esc Esc).

Claude Code's rewind restores the conversation and Write/Edit-tool file
changes, but leaves bash-command artifacts behind and fires no hook. This
script runs when the user sends their next message: if the working tree's
changes vs HEAD exactly match an older turn snapshot (the fingerprint of a
rewind), it hard-resets git to that snapshot so bash artifacts revert too.
The pre-reset state is committed and kept under refs/cursor-backups/ first,
so this is never lossy.

Also commits any user edits made between turns (pre-turn snapshot), so
nothing the user creates can be destroyed mid-turn before ever being
committed.

On UserPromptSubmit, stdout is added to Claude's context — so this script is
silent except when a sync actually happens, in which case it tells Claude
what it did. Always exits 0 (never blocks the prompt).
"""
import json
import os
import subprocess
import sys
import time


def done(note=None):
    if note:
        print(note)
    sys.exit(0)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    cwd = data.get("cwd") or ""
    if cwd and os.path.isdir(cwd):
        os.chdir(cwd)

    if os.path.exists(".claude-git-safety-off"):
        done()  # per-repo kill switch
    if git("rev-parse", "--is-inside-work-tree").returncode != 0:
        done()

    gitdir_probe = git("rev-parse", "--git-dir").stdout.strip()
    for op in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
               "rebase-merge", "rebase-apply"):
        if os.path.exists(os.path.join(gitdir_probe, op)):
            done()  # never commit/reset mid merge/rebase/etc.

    # Log the raw payload for restore-signal research.
    try:
        gitdir = git("rev-parse", "--git-dir").stdout.strip()
        with open(os.path.join(gitdir, "claude-git-safety-payloads.jsonl"),
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
        done()  # clean tree: no rewind happened, nothing to do

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
    # Match snapshots from ANY agent kit (wip(claude), wip(cursor), ...) so
    # both tools can share one repo's journal.
    log = git("log", "--format=%H", "-50", "--grep=^wip(").stdout.split()
    candidates = [c for c in log if c != head]

    # A rewind's fingerprint: EVERY dirty file exactly matches some older
    # snapshot. User edits match no snapshot -> pre-turn commit instead.
    target = None
    for c in candidates:
        if all(commit_blob(c, p) == blob for p, blob in current.items()):
            target = c
            break
    if not target:
        git("add", "-A")
        git("commit", "-q", "--no-verify", "-m",
            "wip(claude): pre-turn snapshot (user edits)")
        done()

    # Detected a rewind. Preserve the current mixed state, keep a findable
    # ref to it, then align the whole tree to the restored turn.
    git("add", "-A")
    git("commit", "-q", "--no-verify", "-m",
        "wip(claude): pre-sync state (before aligning to rewind)")
    git("update-ref", f"refs/cursor-backups/{int(time.time())}", "HEAD")
    git("reset", "--hard", target)
    done(f"[revert-properly] A conversation rewind was detected; the workspace "
         f"has been fully restored to snapshot {target[:8]} (including "
         f"bash-command changes the built-in rewind cannot revert). The "
         f"discarded state is preserved under refs/cursor-backups/.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        done()  # never block the user's prompt
