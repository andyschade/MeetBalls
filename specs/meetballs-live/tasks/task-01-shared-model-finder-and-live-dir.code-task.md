---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Add `mb_find_whisper_model()` and `LIVE_DIR` to common.sh

## Description
Add the shared `mb_find_whisper_model()` function and `LIVE_DIR` constant to `lib/common.sh`. This is the foundation for all subsequent tasks — it eliminates duplicated model search logic in `doctor.sh` and `transcribe.sh`, and establishes the live session directory constant.

## Background
Currently, both `lib/doctor.sh` (lines 48-61) and `lib/transcribe.sh` (lines 38-51) contain duplicate code that searches for whisper model files. The design extracts this into a shared function in `common.sh` following the existing pattern of `mb_detect_audio_backend()`.

The `LIVE_DIR` constant is needed by the new `lib/live.sh` for session directory management.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Section 4.4)

**Additional References:**
- specs/meetballs-live/context.md (codebase patterns — esp. "mb_find_whisper_model Return Convention")
- specs/meetballs-live/plan.md (Step 1)
- specs/meetballs-live/research/existing-patterns.md (Pattern 7: Whisper Model Search)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Add `LIVE_DIR="$MEETBALLS_DIR/live"` constant after `TRANSCRIPTS_DIR` (around line 9)
2. Update `mb_init()` to include `$LIVE_DIR` in the `mkdir -p` call (around line 26)
3. Add `mb_find_whisper_model()` function after `mb_check_disk_space()` (after line 67)
4. Function searches these paths in order:
   - `$WHISPER_CPP_MODEL_DIR` (if environment variable is set)
   - `$HOME/.local/share/whisper.cpp/models`
   - `/usr/local/share/whisper.cpp/models`
5. Function looks for `ggml-${WHISPER_MODEL}.bin` in each path
6. On success: prints absolute path to stdout, returns 0
7. On failure: prints nothing, returns 1
8. Pattern follows `mb_detect_audio_backend()` (common.sh:72-82)

## Dependencies
- None — this is the foundation task

## Implementation Approach
1. **RED**: Write 3 failing tests in `tests/test_common.bats`:
   - A1: Returns model path when found via `WHISPER_CPP_MODEL_DIR`
   - A2: Returns model path from `~/.local/share/whisper.cpp/models` default dir
   - A3: Returns empty + exit 1 when model not found anywhere
2. **GREEN**: Add `LIVE_DIR` constant, update `mb_init()`, implement `mb_find_whisper_model()`
3. **REFACTOR**: Ensure the function follows existing naming/style conventions
4. **VERIFY**: Run `tests/test_common.bats` — all 3 new tests + existing 36 tests pass

## Acceptance Criteria

1. **LIVE_DIR constant exists**
   - Given `lib/common.sh` is sourced
   - When checking `$LIVE_DIR`
   - Then it equals `$MEETBALLS_DIR/live`

2. **mb_init creates live directory**
   - Given `mb_init` is called
   - When checking the filesystem
   - Then `$LIVE_DIR` directory exists

3. **Model found via WHISPER_CPP_MODEL_DIR**
   - Given `WHISPER_CPP_MODEL_DIR` is set to a directory containing `ggml-base.en.bin`
   - When `mb_find_whisper_model` is called
   - Then it prints the absolute path to the model and returns 0

4. **Model found via default path**
   - Given a model file exists at `$HOME/.local/share/whisper.cpp/models/ggml-base.en.bin`
   - When `mb_find_whisper_model` is called (without `WHISPER_CPP_MODEL_DIR`)
   - Then it prints the absolute path to the model and returns 0

5. **Model not found**
   - Given no model file exists in any search path
   - When `mb_find_whisper_model` is called
   - Then it prints nothing and returns 1

6. **No regressions**
   - Given the implementation is complete
   - When running `tests/test_common.bats`
   - Then all existing tests (36) plus 3 new tests pass

## Metadata
- **Complexity**: Low
- **Labels**: common, foundation, refactor
- **Required Skills**: Bash, bats testing
