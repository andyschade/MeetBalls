---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Add `live` command to CLI dispatcher and help text

## Description
Add the `live` command routing to `bin/meetballs` dispatcher and update the help text to include `live` as the first (primary) command.

## Background
`bin/meetballs` uses a case-based dispatcher that lazy-sources lib files and calls `cmd_<name>` functions. The `live` command needs to be added following this existing pattern. Per the design, `live` should be listed first in help text since it's the primary feature.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Section 4.7)

**Additional References:**
- specs/meetballs-live/context.md (Integration Point 5)
- specs/meetballs-live/plan.md (Step 5)
- specs/meetballs-live/research/existing-patterns.md (Pattern 2: CLI Dispatcher)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Add `live)` case to the case statement in `bin/meetballs` (before `record)`)
2. Pattern: `shift; source "$LIB_DIR/live.sh"; cmd_live "$@"`
3. Add `live` as the first command in `show_help()` help text:
   ```
   Commands:
     live         Start a live transcription session with Q&A
     record       Record meeting audio from the microphone
     ...
   ```
4. Test that `meetballs --help` output includes "live"

## Dependencies
- Task 04: `lib/live.sh` must exist with `cmd_live()` function

## Implementation Approach
1. **RED**: Add/update test in `tests/test_meetballs.bats` to verify help text includes "live"
2. **GREEN**: Add `live)` case and help text entry to `bin/meetballs`
3. **VERIFY**: Run `tests/test_meetballs.bats` — new test passes + no regressions

## Acceptance Criteria

1. **Help text includes live**
   - Given `meetballs --help` is run
   - When the output is inspected
   - Then it contains "live" as a listed command

2. **Live command dispatches correctly**
   - Given `lib/live.sh` exists with `cmd_live()`
   - When `meetballs live --help` is run
   - Then it prints live command help (delegated to `cmd_live`)

3. **Live listed first**
   - Given `meetballs --help` is run
   - When inspecting command order
   - Then `live` appears before `record` in the command list

4. **No regressions**
   - Given the changes are complete
   - When running `tests/test_meetballs.bats`
   - Then all existing tests plus the new test pass

## Metadata
- **Complexity**: Low
- **Labels**: cli, dispatcher, help
- **Required Skills**: Bash
