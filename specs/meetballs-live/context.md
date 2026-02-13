# Implementation Context — MeetBalls Live

## Summary of Research Findings

The codebase is clean, well-tested (94/94 bats tests), and follows consistent patterns. The design aligns perfectly with existing conventions. No surprises or undocumented constraints were found.

## Integration Points

### 1. `lib/common.sh` — Add constant + shared helper
- **Add `LIVE_DIR`** at line 9 (after `TRANSCRIPTS_DIR`): `LIVE_DIR="$MEETBALLS_DIR/live"`
- **Add `mb_find_whisper_model()`** after `mb_check_disk_space()` (after line 67). Returns model path on stdout, returns 1 if not found. Search paths match existing code in doctor.sh:50-54 and transcribe.sh:40-44.
- **Update `mb_init()`** at line 26: add `$LIVE_DIR` to `mkdir -p` call.

### 2. `lib/doctor.sh` — Refactor model search + add live section
- **Replace lines 48-67** (model search + reporting) with `mb_find_whisper_model` call.
- **Add live-mode section** after core checks (after current line 87). Three new checks: tmux, whisper-stream, libsdl2.
- **Key behavior:** Core failures set exit code 1. Live-mode failures are reported as warnings only.
- **Summary format changes:** See design.md Section 4.5 for three possible summary messages.

### 3. `lib/transcribe.sh` — Refactor model search
- **Replace lines 38-55** with `mb_find_whisper_model` call. The function returns the path directly, simplifying the code to ~4 lines.
- **Regression risk:** Low — existing tests cover transcribe behavior. The refactor only changes how the model path is found, not what happens with it.

### 4. `lib/live.sh` — New file (core feature)
- Follows existing module pattern: `cmd_live()` entry function.
- No module-level variables needed (unlike record.sh) because cleanup happens after `tmux attach` returns, not in a signal handler.
- Helper scripts are written to session dir as heredocs.
- **Critical:** Helper scripts need variables expanded at generation time (session dir path, model path, timestamp). Use unquoted heredoc (`<<EOF` not `<<'EOF'`) for variable expansion.

### 5. `bin/meetballs` — Add live command
- Add `live)` case at line 47 (before `record)`). Design says live should be first command listed.
- Add `live` to `show_help()` at line 26 (before `record`).

### 6. `install.sh` — Add whisper-stream build step
- Insert new section between step 2 (bats install) and step 3 (symlink). Renumber steps.
- Non-fatal if whisper.cpp source not found.

### 7. `tests/test_live.bats` — New test file
- Follow Pattern C from existing tests (restricted PATH + mocks).
- Need mocks for: tmux, whisper-stream, claude, whisper model file.
- tmux mock needs to handle multiple subcommands (has-session, new-session, split-window, send-keys, attach-session, kill-session).

## Constraints and Considerations

### Variable Expansion in Generated Scripts
The generated `transcriber.sh` and `asker.sh` are written as heredocs inside `cmd_live()`. Variables like `$SESSION_DIR`, `$MODEL_PATH`, and `$TIMESTAMP` must be expanded at generation time (not at runtime of the helper). Use unquoted `<<EOF` delimiter.

### tmux Mock for Tests
The tmux mock needs to be smarter than a simple `exit 0` because multiple tmux subcommands are called. Pattern from test_doctor.bats `create_mock_command "df" '<body>'` shows how to create argument-parsing mocks. The tmux mock should:
- Accept any subcommand without error
- For `has-session`: exit 1 by default (no stale session) or exit 0 in specific tests
- For `attach-session`: exit 0 immediately (simulate detach)
- Record calls for assertion in tests

### PATH Restriction in Tests
Tests for dependency validation must use restricted PATH (`$MOCK_BIN:/usr/bin:/bin`) to prevent real tmux/whisper-stream/claude from being found. This is the established pattern from test_doctor.bats, test_record.bats, etc.

### mb_find_whisper_model Return Convention
The function should:
- Print the absolute path to stdout on success
- Return 0 on success
- Print nothing on failure
- Return 1 on failure

This matches the pattern of `mb_detect_audio_backend()` (`lib/common.sh:72-82`) which prints the backend name and returns 1 if none found. Callers use command substitution: `model_path=$(mb_find_whisper_model)`.

### doctor.sh Exit Code Logic
The design specifies core failures cause exit 1, live-mode failures don't. Implementation needs two separate counters (`core_failures` and `live_failures`). The existing single `failures` counter (`lib/doctor.sh:21`) becomes `core_failures`.

### Cleanup Safety
The design specifies defensive cleanup with `|| true` and existence checks. This is consistent with `lib/record.sh:10-11` which uses `kill ... 2>/dev/null || true` and `wait ... 2>/dev/null || true`.

### No `local` in Generated Scripts
Design critic already caught and fixed this. The generated asker.sh and transcriber.sh are standalone scripts (not functions), so `local` is invalid. All variables are plain assignments. This is correct since each script runs as a separate process.

## File Dependencies (Implementation Order)

```
common.sh (mb_find_whisper_model + LIVE_DIR)
    |
    +-- doctor.sh (refactor model search, add live section)
    +-- transcribe.sh (refactor model search)
    |
    +-- live.sh (new, depends on common.sh additions)
    |
    +-- bin/meetballs (add live command routing)
    |
    +-- install.sh (add whisper-stream build)
    |
    +-- tests/test_live.bats (new, depends on all above)
```

`common.sh` changes must come first. doctor.sh and transcribe.sh refactors can happen in parallel. live.sh depends on common.sh. Tests come last.
