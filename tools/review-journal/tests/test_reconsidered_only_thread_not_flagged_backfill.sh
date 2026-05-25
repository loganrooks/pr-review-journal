#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #1 (Codex P1 finding, montage_cli PR #18).
# A resolved thread with ONLY a `review-verdict-reconsidered` block (no
# primary block) must NOT be flagged BACKFILL NEEDED — it has a valid
# verdict from the reconsidered block.
source "$(dirname "$0")/lib.sh"
start_test "test_reconsidered_only_thread_not_flagged_backfill"

write_threads_fixture "$TEST_WORKDIR/threads.json" '[
  {
    "id": "PRRT_reconsidered_only",
    "isResolved": true, "isOutdated": false,
    "path": "src/a.py", "line": 1,
    "comments": {"nodes": [
      {"id": "c1", "author": {"login": "coderabbitai"},
       "body": "Major: this is the finding.",
       "createdAt": "2026-05-21T20:00:00Z", "url": "https://example/1"},
      {"id": "c2", "author": {"login": "loganrooks"},
       "body": "```review-verdict-reconsidered\nverdict: ACCEPTED\ncommit: abc1234\nreviewer: coderabbitai\nnotes: revisited and accepted after second look.\n```",
       "createdAt": "2026-05-21T20:01:00Z", "url": "https://example/2"}
    ]}
  }
]'

journal_dir="$TEST_WORKDIR/journal"
mkdir -p "$journal_dir"

# Run sync in strict mode; the thread has a valid (reconsidered) verdict so
# strict should pass with exit 0 even though there is no primary block.
set +e
stderr=$("$SYNC_PR" 1 --repo test/repo \
  --threads-from "$TEST_WORKDIR/threads.json" \
  --journal-dir "$journal_dir" \
  --enforce strict 2>&1 >/dev/null)
ec=$?
set -e

assert_exit_code 0 "$ec" "strict mode passes (reconsidered-only counts as having a verdict)"
# Stderr must NOT name the thread as BACKFILL NEEDED.
if echo "$stderr" | grep -qE 'BACKFILL NEEDED.*PRRT_reconsidered_only'; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: reconsidered-only thread was incorrectly flagged BACKFILL NEEDED"
  echo "  stderr: $stderr"
fi

# Verify the journal record HAS the reconsidered verdict applied.
verdict=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['threads'][0]['verdict'])" "$journal_dir/pr-1.json")
assert_eq "ACCEPTED" "$verdict" "reconsidered verdict landed on record"

finish_test
