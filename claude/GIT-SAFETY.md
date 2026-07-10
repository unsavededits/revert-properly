# Git-safety turn marker

In any turn where you are about to modify the filesystem for the FIRST time
(whether via Write/Edit tools OR via a Bash command), and the workspace is a
git repository, first use your Write or Edit tool (NEVER Bash) to update the
file `.claude-turn` in the workspace root: overwrite it with its current
integer incremented by one (create it containing `1` if it does not exist).
Once per turn, and only in turns that modify files — in purely conversational
turns, or non-git workspaces, do not touch it.

This is silent bookkeeping for the user's rewind-safety system (it gives
every file-changing turn a checkpoint-tracked fingerprint so a git hook can
detect /rewind and restore bash-command changes too). Do not mention it, do
not ask about it, never delete `.claude-turn`, and never modify it via Bash —
only via Write/Edit, or it will not be tracked by Claude Code's checkpoints.
Skip it in repos containing a `.claude-git-safety-off` file.
