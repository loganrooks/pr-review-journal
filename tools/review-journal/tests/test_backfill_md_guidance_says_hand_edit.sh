#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #5 (Codex P2 finding, montage_cli PR #18).
# The generated backfill.md must NOT instruct maintainers to use the
# reserved/unimplemented `--accept-inferred` flag. It must instead direct
# them to hand-edit `verdict_source: "manual"` in the journal JSON.
source "$(dirname "$0")/lib.sh"
start_test "test_backfill_md_guidance_says_hand_edit"

write_threads_fixture "$TEST_WORKDIR/threads.json" '[
  {
    "id": "PRRT_to_backfill",
    "isResolved": true, "isOutdated": false,
    "path": "src/a.py", "line": 1,
    "comments": {"nodes": [
      {"id": "c1", "author": {"login": "coderabbitai"},
       "body": "Major: needs work.",
       "createdAt": "2026-05-21T20:00:00Z", "url": "https://example/1"},
      {"id": "c2", "author": {"login": "loganrooks"},
       "body": "Addressed in commit 1234567.",
       "createdAt": "2026-05-21T20:01:00Z", "url": "https://example/2"}
    ]}
  }
]'

journal_dir="$TEST_WORKDIR/journal"
mkdir -p "$journal_dir"

"$EXTRACT_PR" 1 --repo test/repo \
  --threads-from "$TEST_WORKDIR/threads.json" \
  --journal-dir "$journal_dir" >/dev/null 2>&1

backfill_md="$journal_dir/pr-1-backfill.md"
assert_file_exists "$backfill_md" "backfill md exists"

body=$(cat "$backfill_md")

# Guidance must NOT mention --accept-inferred (the reserved/unimplemented flag).
if echo "$body" | grep -q -- '--accept-inferred'; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: backfill.md still references the reserved --accept-inferred flag"
fi

# Guidance must direct the user to hand-edit verdict_source.
assert_contains "verdict_source" "$body" "guidance names verdict_source"
assert_contains "manual" "$body" "guidance names manual as the target value"

finish_test
