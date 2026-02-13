# Broken Windows — MeetBalls

## Status: Minor items found

### lib/common.sh:2 — Missing blank line before constants
**Type**: formatting
**Risk**: Low
**Fix**: Add blank line between module docstring and constants section for readability
**Code**:
```bash
# MeetBalls — Shared utilities sourced by all modules

# Constants
```
Currently has no blank line between `# MeetBalls...` comment and `# Constants`.

### tests/test_common.bats:6-18 — Duplicated setup/teardown
**Type**: duplication
**Risk**: Low
**Fix**: Could reuse test_helper's setup/teardown and add `source "$LIB_DIR/common.sh"` separately, but current approach works and is explicit. No action needed — documenting for awareness.
**Code**:
```bash
setup() {
    export MEETBALLS_DIR="$(mktemp -d)"
    MOCK_BIN="$(mktemp -d)"
    export PATH="$MOCK_BIN:$PATH"
    source "$LIB_DIR/common.sh"
}
```

### specs/meetballs-cli/research/existing-patterns.md — Was stale
**Type**: docs
**Risk**: Low
**Fix**: Updated in this Explorer iteration to reflect current project state (tasks 00-01 complete).

No high-risk broken windows found. Codebase is clean and follows established conventions consistently.
