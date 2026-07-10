#!/bin/bash
# git pre-push hook: refuses to push WIP journal commits.
# Install per repo:
#   cp extras/pre-push-guard.sh <repo>/.git/hooks/pre-push
#   chmod +x <repo>/.git/hooks/pre-push
# Override deliberately with: git push --no-verify

zero=0000000000000000000000000000000000000000
while read -r local_ref local_sha remote_ref remote_sha; do
  [ "$local_sha" = "$zero" ] && continue  # deleting a remote ref
  if [ "$remote_sha" = "$zero" ]; then
    range="$local_sha --not --remotes"
  else
    range="$remote_sha..$local_sha"
  fi
  # shellcheck disable=SC2086
  n=$(git log --oneline --grep='^wip(' $range 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    echo "pre-push guard: $n 'wip(' journal commit(s) in the push range." >&2
    echo "Run /ship (Cursor) or /git-ship (Claude Code) to squash them first," >&2
    echo "or push with --no-verify to override deliberately." >&2
    exit 1
  fi
done
exit 0
