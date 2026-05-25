#!/usr/bin/env bash
# Regression test for v0.1.0 bug fix #3 (Codex P2 finding, montage_cli PR #18).
# A reply containing ONE malformed block and ONE valid verdict block must
# return the valid block (not raise / drop everything). The original
# `parse_all_blocks` raised on the first invalid block, causing the entire
# reply's verdicts to be lost.
source "$(dirname "$0")/lib.sh"
start_test "test_parse_all_blocks_preserves_valid_when_sibling_malformed"

# Build a reply body with: (a) one malformed example block, then (b) one
# valid verdict block. Old behavior: raises on (a), valid (b) is dropped.
# New behavior: skip (a) with a stderr warning, keep (b).
body=$(cat <<'EOF'
This response includes an example block then a real one.

```review-verdict
verdict: TOTALLY_INVALID_VALUE
notes: example only — not a real verdict
```

And the real verdict:

```review-verdict
verdict: ACCEPTED
commit: abc1234
reviewer: coderabbitai
notes: actually accepted.
```
EOF
)

# Use parse-block --all to exercise parse_all_blocks directly.
set +e
result=$(printf '%s' "$body" | python3 "$REVIEW_JOURNAL_PY" parse-block --all 2>/dev/null)
ec=$?
set -e

assert_exit_code 0 "$ec" "parse-block --all exits 0 even with one malformed sibling block"

# Result must contain the valid verdict.
valid_count=$(python3 -c "import json,sys; d = json.loads(sys.argv[1]); print(sum(1 for b in d if b.get('verdict') == 'ACCEPTED'))" "$result")
assert_eq "1" "$valid_count" "valid ACCEPTED block preserved"

# Result must NOT contain the malformed block as a successful parse.
invalid_count=$(python3 -c "import json,sys; d = json.loads(sys.argv[1]); print(sum(1 for b in d if b.get('verdict') == 'TOTALLY_INVALID_VALUE'))" "$result")
assert_eq "0" "$invalid_count" "malformed block correctly skipped"

finish_test
