Reclaim disk space from the git-safety journal in this repository.

1. Report the current size: `du -sh .git`
2. List backup refs with ages:
   `git for-each-ref refs/cursor-backups --format='%(refname:short) %(creatordate:relative)'`
3. Propose deleting the ones older than 30 days (or the age I specify) and
   wait for my confirmation — deleting a backup ref permanently discards the
   ability to un-rewind to that state.
4. On approval, delete each: `git update-ref -d refs/cursor-backups/<name>`
5. Run `git reflog expire --expire=30.days --all && git gc --quiet`
6. Report the size again: `du -sh .git`

If the repo has ballooned from an accidentally-committed dependency or build
directory (check `git count-objects -vH` and large blobs via
`git rev-list --objects --all | sort -k2 | tail`), tell me what you find and
propose options rather than rewriting history on your own.
