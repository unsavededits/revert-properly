#!/bin/bash
# Cursor `stop` hook: snapshot the workspace as a git commit after each agent
# turn that changed anything. Fires on completed, aborted, and errored turns.
# Self-defends against repo bloat: seeds .git/info/exclude with common
# dependency/build directories, and auto-excludes any directory that floods
# the status with untracked files (the `npm install` signature). Exclude
# rules only affect untracked files, so deliberately tracked paths are never
# dropped from the journal.
# Never blocks the agent (stop hooks are observational; always exit 0).

input=$(cat)

root=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    roots = d.get("workspace_roots") or []
    print(roots[0] if roots else "")
except Exception:
    print("")
' 2>/dev/null)

[ -n "$root" ] && [ -d "$root" ] && cd "$root"

# Per-repo kill switch, and not-a-git-repo -> nothing to do.
[ -e ".cursor-git-safety-off" ] && exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

gitdir=$(git rev-parse --git-dir)

# Never snapshot mid merge/rebase/cherry-pick/bisect — a half-done operation
# is not a state worth journaling, and committing could complete it by
# accident (conflict markers and all).
for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
  [ -e "$gitdir/$op" ] && exit 0
done

# Log the raw hook payload (outside the worktree) for research/debugging.
printf '%s\n' "$input" >> "$gitdir/cursor-git-safety-payloads.jsonl" 2>/dev/null

# --- bloat protection ------------------------------------------------------
ex="$gitdir/info/exclude"
mkdir -p "$gitdir/info"
if ! grep -q '# agent-git-safety auto-excludes' "$ex" 2>/dev/null; then
  cat >> "$ex" <<'EOF'
# agent-git-safety auto-excludes (affects untracked files only)
node_modules/
.venv/
venv/
__pycache__/
*.pyc
.DS_Store
dist/
build/
out/
.next/
.nuxt/
target/
coverage/
.cache/
.pytest_cache/
.mypy_cache/
.turbo/
.parcel-cache/
EOF
fi

# Flood guard: if a turn produces 300+ changed paths, exclude the top-level
# directories responsible for >200 untracked files each.
/usr/bin/python3 - "$ex" <<'PY' 2>/dev/null
import subprocess, sys, collections
ex_path = sys.argv[1]
out = subprocess.run(["git", "status", "--porcelain=v1", "-z", "-uall"],
                     capture_output=True, text=True).stdout
entries = [e for e in out.split("\0") if e]
if len(entries) <= 300:
    sys.exit(0)
untracked = [e[3:] for e in entries if e.startswith("??")]
counts = collections.Counter(p.split("/", 1)[0] + "/"
                             for p in untracked if "/" in p)
try:
    existing = set(open(ex_path).read().splitlines())
except OSError:
    existing = set()
with open(ex_path, "a") as f:
    for d, n in counts.items():
        if n > 200 and d not in existing:
            f.write(d + "\n")
PY
# ---------------------------------------------------------------------------

# Nothing changed (after excludes) -> no snapshot.
[ -n "$(git status --porcelain)" ] || exit 0

conv=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("conversation_id", "")[:8])
except Exception:
    print("")
' 2>/dev/null)

status=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("status", ""))
except Exception:
    print("")
' 2>/dev/null)

git add -A
git commit -q --no-verify \
  -m "wip(cursor): turn snapshot $(date +%Y-%m-%dT%H:%M:%S)${conv:+ [conv $conv]}${status:+ ($status)}"

# Opportunistic housekeeping, detached so it never delays anything.
(git gc --auto --quiet >/dev/null 2>&1 &)

exit 0
