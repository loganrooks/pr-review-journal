#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #6 (Codex P2 finding, montage_cli PR #18).
# install/ci-check.yml must guard the `gh pr comment` call so a transient
# API error or restricted fork-PR permission does not turn a warning-mode
# advisory check into a blocking CI failure.
source "$(dirname "$0")/lib.sh"
start_test "test_ci_check_yml_guards_gh_pr_comment"

CI_CHECK_YML="$TOOL_DIR/install/ci-check.yml"
assert_file_exists "$CI_CHECK_YML" "ci-check.yml exists"

# Find the gh pr comment block and confirm it's guarded with `|| ...` so a
# failure cannot fail the workflow step.
guarded=$(awk '
  /gh pr comment/   { in_block = 1; capture = ""; }
  in_block          { capture = capture $0 "\n"; if (/--body-file/) { print capture; in_block = 0; capture = "" } }
' "$CI_CHECK_YML")

# The captured block ends with the --body-file line; the line immediately
# after in the file should be the `|| ...` guard.
guard_line=$(grep -A 1 -- '--body-file /tmp/review-journal.comment.md' "$CI_CHECK_YML" | tail -1)

if ! echo "$guard_line" | grep -qE '\|\|'; then
  TEST_FAILURES=$((TEST_FAILURES + 1))
  echo "FAIL: gh pr comment in ci-check.yml is not guarded with || <fallback>"
  echo "  line after --body-file: $guard_line"
fi

finish_test
