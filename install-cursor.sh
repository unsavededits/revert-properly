#!/bin/bash
# Global install for Cursor. Copies hooks/commands/rules into ~/.cursor and
# merges hook registrations into ~/.cursor/hooks.json non-destructively.
set -e
src="$(cd "$(dirname "$0")/cursor/.cursor" && pwd)"

mkdir -p ~/.cursor/hooks ~/.cursor/commands ~/.cursor/rules
cp "$src/hooks/auto-commit.sh" "$src/hooks/rewind.sh" "$src/hooks/sync-after-restore.py" ~/.cursor/hooks/
chmod +x ~/.cursor/hooks/auto-commit.sh ~/.cursor/hooks/rewind.sh ~/.cursor/hooks/sync-after-restore.py

# Commands (rewind.sh path rewritten to its global location).
sed "s|\.cursor/hooks/rewind\.sh|$HOME/.cursor/hooks/rewind.sh|g" \
  "$src/commands/rewind-properly.md" > ~/.cursor/commands/rewind-properly.md
cp "$src/commands/ship-properly.md" "$src/commands/prune-properly.md" ~/.cursor/commands/

# Rule file (may or may not load globally — see note below).
cp "$src/rules/turn-marker.mdc" ~/.cursor/rules/

python3 - <<'EOF'
import json, os
p = os.path.expanduser("~/.cursor/hooks.json")
home = os.path.expanduser("~")
wanted = {
    "stop": f"{home}/.cursor/hooks/auto-commit.sh",
    "beforeSubmitPrompt": f"{home}/.cursor/hooks/sync-after-restore.py",
}
cfg = {"version": 1, "hooks": {}}
if os.path.exists(p):
    with open(p) as f:
        cfg = json.load(f)
cfg.setdefault("version", 1)
cfg.setdefault("hooks", {})
for event, cmd in wanted.items():
    entries = cfg["hooks"].setdefault(event, [])
    if not any(e.get("command") == cmd for e in entries):
        entries.append({"command": cmd})
with open(p, "w") as f:
    json.dump(cfg, f, indent=2)
print("~/.cursor/hooks.json updated")
EOF

echo
echo "Done. Two manual steps:"
echo "1. Paste the rule text from cursor/.cursor/rules/turn-marker.mdc (below"
echo "   the --- frontmatter) into Cursor Settings -> Rules -> User Rules."
echo "   (Global rule FILES aren't guaranteed to load; the settings box is.)"
echo "2. Reload Window (Cmd+Shift+P) in any open Cursor windows."
