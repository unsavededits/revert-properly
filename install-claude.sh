#!/bin/bash
# Global install for Claude Code. Copies hooks/commands into ~/.claude,
# merges hook registrations into ~/.claude/settings.json non-destructively,
# and includes the turn-marker rule from ~/.claude/CLAUDE.md.
set -e
src="$(cd "$(dirname "$0")/claude" && pwd)"

mkdir -p ~/.claude/hooks ~/.claude/commands
cp "$src/hooks/auto-commit.sh" "$src/hooks/rewind.sh" "$src/hooks/sync-after-restore.py" ~/.claude/hooks/
chmod +x ~/.claude/hooks/auto-commit.sh ~/.claude/hooks/rewind.sh ~/.claude/hooks/sync-after-restore.py
cp "$src/commands/rewind-properly.md" "$src/commands/ship-properly.md" "$src/commands/prune-properly.md" ~/.claude/commands/
cp "$src/GIT-SAFETY.md" ~/.claude/GIT-SAFETY.md

python3 - <<'EOF'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
home = os.path.expanduser("~")
wanted = {
    "Stop": f"{home}/.claude/hooks/auto-commit.sh",
    "UserPromptSubmit": f"{home}/.claude/hooks/sync-after-restore.py",
}
cfg = {}
if os.path.exists(p):
    with open(p) as f:
        cfg = json.load(f)
hooks = cfg.setdefault("hooks", {})
for event, cmd in wanted.items():
    entries = hooks.setdefault(event, [])
    present = any(
        h.get("command") == cmd
        for e in entries for h in e.get("hooks", [])
    )
    if not present:
        entries.append({"hooks": [{"type": "command", "command": cmd}]})
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
print("~/.claude/settings.json updated")
EOF

touch ~/.claude/CLAUDE.md
grep -qxF '@GIT-SAFETY.md' ~/.claude/CLAUDE.md || printf '\n@GIT-SAFETY.md\n' >> ~/.claude/CLAUDE.md

echo
echo "Done. Takes effect in NEW Claude Code sessions (hooks load at session"
echo "start). Commands: /rewind-properly, /ship-properly, /prune-properly."
