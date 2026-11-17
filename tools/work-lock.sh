#!/usr/bin/env bash
# One Claude at a time on master. The lock is WORK-LOCK.md on the remote
# master branch, so every clone and every session sees the same state.
#
#   tools/work-lock.sh status          show who holds it (exit 0 free/yours, 1 busy)
#   tools/work-lock.sh take "task"     take it (exit 0), or exit 1 if someone else has it
#   tools/work-lock.sh wait "task"     wait until it is free, then take it
#   tools/work-lock.sh release         give it back (only the holder can)
#
# Taking and releasing are commits pushed to master. A push only succeeds
# on top of the latest master, so two sessions can never both take it: the
# loser's push is rejected, it re-reads the lock and sees it busy.
# The lock changes only WORK-LOCK.md, in a throwaway worktree — your own
# checkout and uncommitted work are never touched.
#
# A lock older than WORK_LOCK_STALE_HOURS (default 3) counts as abandoned
# (a session that crashed), so nobody waits forever. `take` again while you
# hold it refreshes the time.
set -euo pipefail

REMOTE=${WORK_LOCK_REMOTE:-origin}
BRANCH=${WORK_LOCK_BRANCH:-master}
FILE=WORK-LOCK.md
STALE_HOURS=${WORK_LOCK_STALE_HOURS:-3}
POLL=${WORK_LOCK_POLL_SECONDS:-60}
MAX_WAIT=${WORK_LOCK_MAX_WAIT_SECONDS:-21600}

ROOT=$(git rev-parse --show-toplevel)
GITDIR=$(git rev-parse --git-common-dir)
# Who "I" am: one random id per clone (a cloud session is its own clone).
ID_FILE="$GITDIR/work-lock-id"
[ -s "$ID_FILE" ] || { printf 'claude-%s\n' "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" > "$ID_FILE"; }
ME=$(cat "$ID_FILE")

field() { sed -n "s/^- $1: //p" <<<"$2" | head -1; }

read_lock() {
  git -C "$ROOT" fetch -q "$REMOTE" "$BRANCH"
  git -C "$ROOT" show "FETCH_HEAD:$FILE" 2>/dev/null || printf -- '- status: free\n'
}

# 0 = free or mine, 1 = someone else holds it.
check() {
  local lock status by since now age
  lock=$(read_lock)
  status=$(field status "$lock"); by=$(field by "$lock"); since=$(field since "$lock")
  if [ "$status" != "in-use" ]; then echo "free"; return 0; fi
  if [ "$by" = "$ME" ]; then echo "yours (since $since)"; return 0; fi
  now=$(date -u +%s)
  age=$(( now - $(date -u -d "$since" +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$since" +%s 2>/dev/null || echo "$now") ))
  if [ "$age" -ge $(( STALE_HOURS * 3600 )) ]; then
    echo "abandoned: $by since $since (older than ${STALE_HOURS} h) — counts as free"; return 0
  fi
  echo "busy: $by since $since — $(field task "$lock")"; return 1
}

# Write the lock file in a throwaway worktree on top of the remote branch and push.
write_lock() {
  local content=$1 message=$2 tmp
  tmp=$(mktemp -d)
  git -C "$ROOT" worktree add -q --detach "$tmp" FETCH_HEAD
  printf '%s\n' "$content" > "$tmp/$FILE"
  git -C "$tmp" add "$FILE"
  local ok=0
  if git -C "$tmp" commit -q -m "$message [skip ci]" && git -C "$tmp" push -q "$REMOTE" "HEAD:$BRANCH" 2>/dev/null; then ok=1; fi
  git -C "$ROOT" worktree remove --force "$tmp"
  [ "$ok" = 1 ]
}

header='# Work lock

Only one Claude session changes master at a time. Read CLAUDE.md, "Working
together", before you start. Use `tools/work-lock.sh`; do not edit this by hand.
'

take() {
  local task=${1:-work} tries
  for tries in 1 2 3 4 5; do
    check >/dev/null || { check || true; return 1; }
    local now; now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if write_lock "$header
- status: in-use
- by: $ME
- since: $now
- task: $task" "work-lock: in use — $task"; then
      echo "taken by $ME at $now"; return 0
    fi
    sleep $(( tries * 2 ))   # master moved under us: read the lock again
  done
  echo "could not push the lock after 5 tries" >&2; return 2
}

release() {
  local lock tries
  for tries in 1 2 3 4 5; do
    lock=$(read_lock)
    if [ "$(field status "$lock")" != "in-use" ]; then echo "already free"; return 0; fi
    if [ "$(field by "$lock")" != "$ME" ]; then echo "not yours: $(field by "$lock") holds it" >&2; return 1; fi
    if write_lock "$header
- status: free
- since: $(date -u +%Y-%m-%dT%H:%M:%SZ)" "work-lock: free"; then echo "released"; return 0; fi
    sleep $(( tries * 2 ))
  done
  echo "could not push the release after 5 tries" >&2; return 2
}

wait_take() {
  local waited=0
  until take "${1:-work}"; do
    [ "$waited" -ge "$MAX_WAIT" ] && { echo "gave up after ${MAX_WAIT}s" >&2; return 1; }
    sleep "$POLL"; waited=$(( waited + POLL ))
  done
}

case "${1:-status}" in
  status) check ;;
  take) take "${2:-work}" ;;
  wait) wait_take "${2:-work}" ;;
  release) release ;;
  whoami) echo "$ME" ;;
  *) echo "usage: $0 status|take \"task\"|wait \"task\"|release|whoami" >&2; exit 64 ;;
esac
