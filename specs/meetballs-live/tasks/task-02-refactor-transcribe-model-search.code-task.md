---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Refactor `transcribe.sh` to use `mb_find_whisper_model`

## Description
Replace the inline model search logic in `lib/transcribe.sh` (lines 38-55) with a call to the new shared `mb_find_whisper_model()` function. This eliminates code duplication while preserving identical behavior.

## Background
`lib/transcribe.sh` contains 18 lines of model search logic (lines 38-55) that duplicate `lib/doctor.sh` (lines 48-61). Task 01 extracted this into `mb_find_whisper_model()` in `common.sh`. This task is a pure refactor — the external behavior of `cmd_transcribe` does not change.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Section 4.6)

**Additional References:**
- specs/meetballs-live/context.md (Integration Point 3)
- specs/meetballs-live/plan.md (Step 2)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Replace lines 38-55 in `lib/transcribe.sh` with:
   ```bash
   local model_path
   model_path=$(mb_find_whisper_model)
   if [[ -z "$model_path" ]]; then
       mb_die "Whisper model not found (ggml-${WHISPER_MODEL}.bin). Download it with: whisper-cli -dl $WHISPER_MODEL"
   fi
   ```
2. The error message must be identical or equivalent to the existing one
3. The `$model_path` variable must be used in the same way the previous `$MODEL_PATH` was used downstream

## Dependencies
- Task 01: `mb_find_whisper_model()` must exist in `common.sh`

## Implementation Approach
1. Read the current `lib/transcribe.sh` to understand exact usage of the model path variable downstream
2. Replace the inline model search with the `mb_find_whisper_model` call
3. Verify variable naming matches downstream usage (the variable used after the search block)
4. **VERIFY**: Run `tests/test_transcribe.bats` — all existing tests pass (regression-only, no new tests)

## Acceptance Criteria

1. **Inline model search removed**
   - Given `lib/transcribe.sh` is inspected
   - When looking for the model search logic
   - Then the 18 lines of inline search (old lines 38-55) are replaced by a ~4-line `mb_find_whisper_model` call

2. **Behavior preserved**
   - Given a whisper model exists in the standard location
   - When running `meetballs transcribe --help`
   - Then it still prints usage information as before

3. **Error on missing model preserved**
   - Given no whisper model exists
   - When `cmd_transcribe` tries to find the model
   - Then it exits with error mentioning the model filename and download instructions

4. **No regressions**
   - Given the refactor is complete
   - When running `tests/test_transcribe.bats`
   - Then all existing tests pass

## Metadata
- **Complexity**: Low
- **Labels**: refactor, transcribe
- **Required Skills**: Bash
