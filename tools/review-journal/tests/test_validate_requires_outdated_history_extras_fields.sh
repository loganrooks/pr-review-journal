#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #4 (Codex P2 finding, montage_cli PR #18).
# REQUIRED_THREAD_FIELDS must include `outdated`, `verdict_refs`,
# `verdict_history`, and `extras` (all fields the tool writes on every
# record and the README documents as part of the schema). A hand-edited
# journal missing any of them must FAIL validation.
source "$(dirname "$0")/lib.sh"
start_test "test_validate_requires_outdated_history_extras_fields"

# Baseline — full record with all required fields passes.
cat > "$TEST_WORKDIR/full.json" <<'EOF'
{
  "schema_version": "1.0",
  "pr_number": 1,
  "repo": "x/y",
  "last_synced_at": "2026-05-22T00:00:00Z",
  "threads": [
    {
      "id": "PRRT_full",
      "path": "x.py", "line": 1,
      "reviewer": "coderabbitai", "reviewer_kind": "bot:agentic-llm",
      "severity": "minor", "category": null,
      "finding_excerpt": "x", "created_at": "2026-05-21T00:00:00Z",
      "resolved": true,
      "verdict": "ACCEPTED", "verdict_commit": "abc1234",
      "verdict_notes": null, "verdict_source": "block",
      "reconsidered_verdict": null,
      "outdated": false, "verdict_refs": [], "verdict_history": [], "extras": {}
    }
  ]
}
EOF
set +e
python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/full.json" >/dev/null 2>&1
full_ec=$?
set -e
assert_exit_code 0 "$full_ec" "full record passes validation"

# For each of the four newly-required fields, strip it and confirm validate fails.
for field in outdated verdict_refs verdict_history extras; do
  python3 -c "
import json, sys
d = json.load(open('$TEST_WORKDIR/full.json'))
del d['threads'][0]['$field']
json.dump(d, open('$TEST_WORKDIR/missing-${field}.json', 'w'))
"
  set +e
  err=$(python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/missing-${field}.json" 2>&1 >/dev/null)
  ec=$?
  set -e
  if [ "$ec" -eq 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
    echo "FAIL: validate did not reject record missing required field '$field'"
  fi
  assert_contains "$field" "$err" "error names missing field '$field'"
done

finish_test
