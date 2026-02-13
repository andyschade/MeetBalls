# MeetBalls Live — Implementation Plan

## Test Strategy

### Unit Tests

#### A. `mb_find_whisper_model()` (in `tests/test_common.bats`)
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1 | Returns model path when found via `WHISPER_CPP_MODEL_DIR` | Model file in `$WHISPER_CPP_MODEL_DIR` | Prints absolute path, exit 0 |
| 2 | Returns model path from `~/.local/share/whisper.cpp/models` | Model file in default dir | Prints absolute path, exit 0 |
| 3 | Returns empty + exit 1 when model not found | No model file anywhere | No output, exit 1 |

#### B. `cmd_live --help` (in `tests/test_live.bats`)
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1 | `--help` prints usage | `meetballs live --help` | Output contains "Usage", exit 0 |

#### C. `cmd_live` dependency validation (in `tests/test_live.bats`)
| # | Test | Mocks Present | Expected |
|---|------|---------------|----------|
| 2 | Missing tmux exits 1 | None | Error mentions "tmux", exit 1 |
| 3 | Missing whisper-stream exits 1 | tmux | Error mentions "whisper-stream", exit 1 |
| 4 | Missing claude exits 1 | tmux, whisper-stream | Error mentions "claude", exit 1 |
| 5 | Missing model exits 1 | tmux, whisper-stream, claude | Error mentions "model", exit 1 |

#### D. `cmd_live` session setup (in `tests/test_live.bats`)
| # | Test | Setup | Expected |
|---|------|-------|----------|
| 6 | Session directory created | All deps mocked, tmux mock returns immediately | Dir exists under `$LIVE_DIR` |
| 7 | Helper scripts generated | Same setup | `transcriber.sh` and `asker.sh` exist in session dir |
| 8 | Stale session killed before new one | tmux `has-session` returns 0 (stale exists) | `kill-session` called before `new-session` |

#### E. `cmd_doctor` live-mode section (in `tests/test_doctor.bats`)
| # | Test | Setup | Expected |
|---|------|-------|----------|
| 9 | Doctor shows live-mode section | All core + live deps mocked | Output contains "Live mode" |
| 10 | Doctor core-only failure still exits 1 | Missing audio, live deps present | Exit 1 |
| 11 | Doctor live-only failure does NOT exit 1 | All core deps present, missing tmux | Exit 0, output contains warning about tmux |

### Integration Tests

#### F. Refactored modules still work (existing test coverage)
| Module | Verification |
|--------|-------------|
| `transcribe.sh` | Existing test_transcribe.bats tests pass after model search refactor |
| `doctor.sh` | Existing test_doctor.bats tests pass after model search refactor + live section addition |
| `common.sh` | Existing test_common.bats tests pass after `mb_find_whisper_model` + `LIVE_DIR` additions |

#### G. CLI dispatcher (in `tests/test_meetballs.bats`)
| # | Test | Input | Expected |
|---|------|-------|----------|
| 12 | Help text includes live command | `meetballs --help` | Output contains "live" |

### E2E Test Scenario (Manual Verification)

**Preconditions:** tmux, whisper-stream, claude CLI, and whisper model all installed.

1. Run `meetballs doctor` — verify it shows both Core and Live mode sections, all checks pass
2. Run `meetballs live` — verify tmux split-pane TUI opens
3. Speak into microphone — verify text appears in top pane
4. Type a question in bottom pane (e.g., "What was just said?") — verify Claude answers based on transcript
5. Type `quit` in bottom pane — verify session ends
6. Verify output: "Transcript saved: ~/.meetballs/transcripts/<ts>.txt"
7. Verify output: "Recording saved: ~/.meetballs/recordings/<ts>.wav"
8. Run `meetballs list` — verify the live session recording appears
9. Run `meetballs live` again, then Ctrl+C in top pane — verify cleanup runs
10. Run `meetballs live` again, then Ctrl+B D to detach — verify cleanup runs

**Success:** All 10 steps produce expected behavior.

## Implementation Steps

### Step 1: Add `mb_find_whisper_model()` to `common.sh` + tests

**Files to create/modify:**
- `lib/common.sh` — Add `LIVE_DIR` constant (line 9), update `mb_init()` (line 26), add `mb_find_whisper_model()` (after line 67)
- `tests/test_common.bats` — Add 3 new tests (A1–A3)

**Tests that should pass after this step:**
- A1: `mb_find_whisper_model` returns path when found via `WHISPER_CPP_MODEL_DIR`
- A2: `mb_find_whisper_model` returns path from default dir
- A3: `mb_find_whisper_model` returns empty + exit 1 when not found
- All existing 36 test_common.bats tests (regression)

**Implementation details:**
- `LIVE_DIR="$MEETBALLS_DIR/live"` after `TRANSCRIPTS_DIR` (line 8)
- `mb_init()`: add `$LIVE_DIR` to `mkdir -p` call
- `mb_find_whisper_model()`: search `$WHISPER_CPP_MODEL_DIR`, `$HOME/.local/share/whisper.cpp/models`, `/usr/local/share/whisper.cpp/models` for `ggml-${WHISPER_MODEL}.bin`. Print path on stdout, return 0 on success, return 1 on failure (no output).

**Demo:** `source lib/common.sh && mb_find_whisper_model` prints the model path.

### Step 2: Refactor `transcribe.sh` to use `mb_find_whisper_model`

**Files to modify:**
- `lib/transcribe.sh` — Replace lines 38–55 with `mb_find_whisper_model` call

**Tests that should pass after this step:**
- All existing test_transcribe.bats tests (regression — verifies refactor is safe)

**Implementation details:**
Replace the inline model search with:
```bash
local model_path
model_path=$(mb_find_whisper_model)
if [[ -z "$model_path" ]]; then
    mb_die "Whisper model not found (ggml-${WHISPER_MODEL}.bin). Download it with: whisper-cli -dl $WHISPER_MODEL"
fi
```

**Connects to:** Step 1 (depends on `mb_find_whisper_model`)

**Demo:** `meetballs transcribe --help` still works; existing tests pass.

### Step 3: Refactor `doctor.sh` to use `mb_find_whisper_model` + add live-mode section + tests

**Files to modify:**
- `lib/doctor.sh` — Replace lines 48–67 model search with `mb_find_whisper_model` call; add live-mode section after core checks; update summary logic with two counters
- `tests/test_doctor.bats` — Add 3 new tests (E9–E11)

**Tests that should pass after this step:**
- E9: Doctor shows live-mode section
- E10: Doctor core-only failure still exits 1
- E11: Doctor live-only failure does NOT exit 1
- All existing test_doctor.bats tests (regression)

**Implementation details:**
- Model check (section 3) uses `mb_find_whisper_model` instead of inline search
- Add `live_failures=0` counter separate from existing `failures` (renamed to `core_failures`)
- Live-mode section checks: `tmux`, `whisper-stream`, `libsdl2` (via `dpkg -s libsdl2-dev`)
- Summary: three possible messages per design Section 4.5
- Test mocking: `setup_all_deps` updated to also mock tmux, whisper-stream, dpkg for live section; new tests use selective mocking

**Connects to:** Step 1 (depends on `mb_find_whisper_model`)

**Demo:** `meetballs doctor` shows "Live mode:" section with tmux/whisper-stream/libsdl2 checks.

### Step 4: Implement `lib/live.sh` + tests

**Files to create/modify:**
- `lib/live.sh` — New file: `cmd_live()` with help, dependency validation, session setup, script generation, tmux orchestration, cleanup
- `tests/test_live.bats` — New file: 8 tests (B1, C2–C5, D6–D8)

**Tests that should pass after this step:**
- B1: `--help` prints usage
- C2: Missing tmux exits 1
- C3: Missing whisper-stream exits 1
- C4: Missing claude exits 1
- C5: Missing model exits 1
- D6: Session directory created
- D7: Helper scripts generated
- D8: Stale session killed

**Implementation details:**

`cmd_live()` flow:
1. `--help` check (heredoc with `'EOF'`)
2. Dependency validation: `tmux`, `whisper-stream`, `claude` (via `mb_check_command` + `mb_die`), then model (via `mb_find_whisper_model`)
3. `mb_init` + `mb_check_disk_space || true`
4. Kill stale session: `tmux has-session -t meetballs-live 2>/dev/null && tmux kill-session -t meetballs-live`
5. Create session dir: `SESSION_DIR="$LIVE_DIR/$(mb_timestamp)"; mkdir -p "$SESSION_DIR"`
6. Generate `transcriber.sh` via unquoted heredoc (`<<EOF`) — variables expand at write time
7. Generate `asker.sh` via unquoted heredoc
8. Create tmux session: `tmux new-session -d -s meetballs-live -x 200 -y 50`
9. Split window: `tmux split-window -v -t meetballs-live -p 20`
10. Send scripts: `tmux send-keys -t meetballs-live:0.0 "bash $SESSION_DIR/transcriber.sh" Enter`
11. Send asker: `tmux send-keys -t meetballs-live:0.1 "bash $SESSION_DIR/asker.sh" Enter`
12. Attach: `tmux attach-session -t meetballs-live` (blocks)
13. Cleanup after attach returns

tmux mock for tests:
```bash
create_mock_command "tmux" '
echo "tmux $*" >> "$MEETBALLS_DIR/.tmux-calls"
case "$1" in
    has-session) exit ${TMUX_HAS_SESSION_EXIT:-1} ;;
    attach-session) exit 0 ;;
    *) exit 0 ;;
esac'
```

**Connects to:** Steps 1–3 (depends on `mb_find_whisper_model`, `LIVE_DIR`, `mb_init`)

**Demo:** `meetballs live --help` prints usage; `meetballs live` with missing deps shows clear errors; with all deps, launches tmux TUI.

### Step 5: Add `live` command to CLI dispatcher + update help

**Files to modify:**
- `bin/meetballs` — Add `live)` case before `record)` (line 47); add `live` to `show_help()` (line 26)

**Tests that should pass after this step:**
- G12: Help text includes "live" command (existing test_meetballs.bats already tests help — may need updating or new test)
- All test_live.bats tests (B1, C2–C5 now also work via `meetballs live` CLI path)

**Implementation details:**
- Add `live` as first command in help text (it's the primary feature)
- Add `live)` case that sources `lib/live.sh` and calls `cmd_live "$@"`

**Connects to:** Step 4 (depends on `lib/live.sh` existing)

**Demo:** `meetballs --help` shows `live` command; `meetballs live --help` works end-to-end.

### Step 6: Update `install.sh` with whisper-stream build step

**Files to modify:**
- `install.sh` — Add step 2b between bats install (step 2) and symlink (step 3)

**Tests that should pass after this step:**
- Existing test_install.bats tests (regression)

**Implementation details:**
- Check if `whisper-stream` already on PATH → skip if found
- Check `dpkg -s libsdl2-dev` → prompt to install if missing
- Locate whisper.cpp source: `$WHISPER_CPP_DIR`, `$HOME/whisper.cpp`, `/usr/local/src/whisper.cpp`
- Build: `cmake -B build -DWHISPER_SDL2=ON && cmake --build build --target stream`
- Copy binary: `sudo cp build/bin/stream /usr/local/bin/whisper-stream`
- Non-fatal: if source not found, print instructions and skip

**Connects to:** Independent (no code dependencies, but logically related)

**Demo:** Running `install.sh` on a fresh system builds and installs whisper-stream.

### Step 7: Full regression run

**Files:** None (verification only)

**Tests that should pass after this step:**
- ALL tests: existing 94 + new tests from steps 1, 3, 4, 5 (~110+ total)

**Verification commands:**
```bash
./tests/libs/bats/bin/bats tests/
```

**Demo:** Clean test run with 0 failures.

## Summary

| Step | What | Files | New Tests | Risk |
|------|------|-------|-----------|------|
| 1 | `mb_find_whisper_model` + `LIVE_DIR` | common.sh, test_common.bats | 3 | Low |
| 2 | Refactor transcribe.sh | transcribe.sh | 0 (regression) | Low |
| 3 | Refactor doctor.sh + live section | doctor.sh, test_doctor.bats | 3 | Medium |
| 4 | `lib/live.sh` core feature | live.sh, test_live.bats | 8 | High |
| 5 | CLI dispatcher + help | bin/meetballs | 1 | Low |
| 6 | install.sh whisper-stream | install.sh | 0 (regression) | Low |
| 7 | Full regression | — | — | — |

**Total new tests:** ~15
**TDD rhythm:** Each step writes tests first (for new test steps), then implements, then verifies.
**Critical path:** Step 1 → Steps 2+3 (parallel) → Step 4 → Step 5. Step 6 is independent.
