#!/usr/bin/env bash
# Pins: the reserved `extras.outcome` key (cross-repo OQ-004) is shape-checked by
# `validate` — a valid outcome passes, a typo'd status/signal fails, and a record
# with no outcome is unaffected (the check is a no-op unless the key is present).
source "$(dirname "$0")/lib.sh"
start_test "test_validate_outcome_linkage_shape"

# A reusable, otherwise-valid thread record. $1 is spliced in as the `extras`
# value so each case varies only the outcome shape.
emit_journal() {
  local extras="$1"
  cat <<EOF
{
  "schema_version": "1.0",
  "pr_number": 99,
  "repo": "x/y",
  "last_synced_at": "2026-05-22T00:00:00Z",
  "threads": [
    {
      "id": "PRRT_outcome",
      "path": "x.swift", "line": 1,
      "reviewer": "coderabbitai", "reviewer_kind": "bot:agentic-llm",
      "severity": "minor", "category": null,
      "finding_excerpt": "test", "created_at": "2026-05-21T00:00:00Z",
      "resolved": true,
      "verdict": "ACCEPTED", "verdict_commit": "abc1234",
      "verdict_notes": null, "verdict_source": "block",
      "reconsidered_verdict": null,
      "outdated": false, "verdict_refs": [], "verdict_history": [],
      "extras": $extras
    }
  ]
}
EOF
}

# Case A — a fully-formed outcome validates clean.
emit_journal '{"outcome": {"status": "CONTRADICTED", "signal": "revert", "ref": "9c1f2ab", "observed_at": "2026-06-10T14:00:00Z", "notes": "reverted later"}}' \
  > "$TEST_WORKDIR/good-outcome.json"
set +e
python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/good-outcome.json" >/dev/null 2>&1
good_ec=$?
set -e
assert_exit_code 0 "$good_ec" "valid extras.outcome passes"

# Case B — an invalid status is rejected and named.
emit_journal '{"outcome": {"status": "MAYBE"}}' > "$TEST_WORKDIR/bad-status.json"
set +e
err=$(python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/bad-status.json" 2>&1 >/dev/null)
bad_status_ec=$?
set -e
if [ "$bad_status_ec" -eq 0 ]; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: invalid outcome.status should fail validation"
fi
assert_contains "MAYBE" "$err" "error names the invalid status value"
assert_contains "outcome.status" "$err" "error points at extras.outcome.status"

# Case C — an invalid signal is rejected and named.
emit_journal '{"outcome": {"status": "CONFIRMED", "signal": "exploded"}}' > "$TEST_WORKDIR/bad-signal.json"
set +e
err=$(python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/bad-signal.json" 2>&1 >/dev/null)
bad_signal_ec=$?
set -e
if [ "$bad_signal_ec" -eq 0 ]; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: invalid outcome.signal should fail validation"
fi
assert_contains "exploded" "$err" "error names the invalid signal value"

# Case D — a lenient outcome (only a human note, no status/signal yet) passes.
emit_journal '{"outcome": {"notes": "audit pending"}}' > "$TEST_WORKDIR/lenient-outcome.json"
set +e
python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/lenient-outcome.json" >/dev/null 2>&1
lenient_ec=$?
set -e
assert_exit_code 0 "$lenient_ec" "partial outcome (no status/signal) passes — UNKNOWN is the default"

# Case E — regression guard: a record with no outcome at all is unaffected.
emit_journal '{}' > "$TEST_WORKDIR/no-outcome.json"
set +e
python3 "$REVIEW_JOURNAL_PY" validate "$TEST_WORKDIR/no-outcome.json" >/dev/null 2>&1
none_ec=$?
set -e
assert_exit_code 0 "$none_ec" "record with empty extras still validates (check is a no-op)"

finish_test
