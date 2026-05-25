#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #2 (Codex P1 finding, montage_cli PR #18).
# An UNRESOLVED thread with only a `review-verdict-reconsidered` block (no
# primary block) MUST be flagged RESOLVE NEEDED in strict mode, the same way
# an unresolved thread with a primary block would be.
source "$(dirname "$0")/lib.sh"
start_test "test_reconsidered_only_unresolved_flagged_resolve_needed"

write_threads_fixture "$TEST_WORKDIR/threads.json" '[
  {
    "id": "PRRT_reconsidered_unresolved",
    "isResolved": false, "isOutdated": false,
    "path": "src/a.py", "line": 1,
    "comments": {"nodes": [
      {"id": "c1", "author": {"login": "coderabbitai"},
       "body": "Major: open finding.",
       "createdAt": "2026-05-21T20:00:00Z", "url": "https://example/1"},
      {"id": "c2", "author": {"login": "loganrooks"},
       "body": "```review-verdict-reconsidered\nverdict: ACCEPTED\ncommit: abc1234\nreviewer: coderabbitai\nnotes: revisited.\n```",
       "createdAt": "2026-05-21T20:01:00Z", "url": "https://example/2"}
    ]}
  }
]'

journal_dir="$TEST_WORKDIR/journal"
mkdir -p "$journal_dir"

set +e
stderr=$("$SYNC_PR" 1 --repo test/repo \
  --threads-from "$TEST_WORKDIR/threads.json" \
  --journal-dir "$journal_dir" \
  --enforce strict 2>&1 >/dev/null)
ec=$?
set -e

# Strict mode MUST exit nonzero — the thread has a verdict but is unresolved.
if [ "$ec" -eq 0 ]; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: strict mode should exit nonzero when a reconsidered-only thread is unresolved"
fi
assert_contains "RESOLVE NEEDED" "$stderr" "stderr names the resolve-needed condition"
assert_contains "PRRT_reconsidered_unresolved" "$stderr" "stderr names the thread"

finish_test
