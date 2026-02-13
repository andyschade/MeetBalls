---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Refactor `doctor.sh` model search + add live-mode section

## Description
Refactor `lib/doctor.sh` to use the shared `mb_find_whisper_model()` for model checking, and add a new "Live mode" section that checks for `tmux`, `whisper-stream`, and `libsdl2-dev`. Core check failures cause exit 1; live-mode check failures are warnings only.

## Background
`lib/doctor.sh` has two changes:
1. **Refactor**: Replace duplicated model search (lines 48-67) with `mb_find_whisper_model` call
2. **New feature**: Add live-mode dependency section with separate failure tracking

The key design decision is that live-mode failures must NOT cause exit 1 — this ensures existing commands (`record`, `transcribe`, `ask`, `list`) still work even if live-mode deps are missing.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Section 4.5)

**Additional References:**
- specs/meetballs-live/context.md (Integration Point 2 — doctor.sh exit code logic)
- specs/meetballs-live/plan.md (Step 3)
- specs/meetballs-live/research/existing-patterns.md (Pattern 5: Dependency Checking)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Replace inline model search (lines 48-67) with `mb_find_whisper_model` call
2. Rename existing `failures` counter to `core_failures` (or similar) to distinguish from live failures
3. Add `live_failures` counter
4. Add "Live mode:" section after core checks with these checks:
   - `tmux` — via `mb_check_command` or `command -v`
   - `whisper-stream` — via `mb_check_command` or `command -v`
   - `libsdl2` — via `dpkg -s libsdl2-dev 2>/dev/null`
5. Summary messages (3 variants per design):
   - `All checks passed.` (0 core + 0 live failures)
   - `All core checks passed. N live-mode check(s) failed.` (0 core + N live failures)
   - `N check(s) failed.` (N core failures, regardless of live)
6. Exit code: `exit $core_failures` (only core failures affect exit code)

## Dependencies
- Task 01: `mb_find_whisper_model()` must exist in `common.sh`

## Implementation Approach
1. **RED**: Write 3 failing tests in `tests/test_doctor.bats`:
   - E9: Doctor shows "Live mode" section when all deps (core + live) are mocked
   - E10: Doctor core-only failure still exits 1 (missing audio, live deps present)
   - E11: Doctor live-only failure does NOT exit 1 (all core deps present, missing tmux) — output contains warning
2. **GREEN**: Implement the model search refactor and live-mode section
3. **REFACTOR**: Ensure output formatting is consistent with existing section
4. **VERIFY**: Run `tests/test_doctor.bats` — all 3 new tests + existing tests pass

## Acceptance Criteria

1. **Live mode section displayed**
   - Given all core and live-mode dependencies are available
   - When running `meetballs doctor`
   - Then output contains a "Live mode" section with tmux, whisper-stream, and libsdl2 checks

2. **Core failure exits 1**
   - Given a core dependency (e.g., audio) is missing but live deps are present
   - When running `meetballs doctor`
   - Then exit code is 1

3. **Live-only failure exits 0**
   - Given all core deps are present but tmux is missing
   - When running `meetballs doctor`
   - Then exit code is 0 and output contains a warning about the missing live dep

4. **Model search uses shared function**
   - Given `lib/doctor.sh` is inspected
   - When looking for model search logic
   - Then it uses `mb_find_whisper_model` instead of inline search

5. **Summary messages are correct**
   - Given various combinations of core and live failures
   - When checking the final summary line
   - Then it matches the 3-variant format from the design

6. **No regressions**
   - Given the implementation is complete
   - When running `tests/test_doctor.bats`
   - Then all existing tests plus 3 new tests pass

## Metadata
- **Complexity**: Medium
- **Labels**: doctor, refactor, live-mode
- **Required Skills**: Bash, bats testing
