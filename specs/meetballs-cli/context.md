# MeetBalls — Implementation Context

## Summary

Partially implemented bash CLI project. Common utilities (`lib/common.sh`) and CLI dispatcher (`bin/meetballs`) are complete with 44 passing tests. Five command modules remain: doctor, list, record, transcribe, ask. All modules follow the same pattern: `lib/<command>.sh` with `cmd_<command>` entry function, sourced lazily by the dispatcher.

## Current Implementation Status

| Component | Status | Tests | File |
|-----------|--------|-------|------|
| Project scaffolding | DONE | 7/7 pass | — |
| lib/common.sh | DONE | 29/29 pass | 114 lines |
| bin/meetballs | DONE | 8/8 pass | 70 lines |
| lib/doctor.sh | NOT STARTED | — | — |
| lib/list.sh | NOT STARTED | — | — |
| lib/record.sh | NOT STARTED | — | — |
| lib/transcribe.sh | NOT STARTED | — | — |
| lib/ask.sh | NOT STARTED | — | — |
| install.sh (finalize) | PARTIAL | — | 29 lines (bats only) |

## Key Established Patterns (Builder must follow)

### Module Structure
Each command module must:
1. Be a sourceable file at `lib/<command>.sh` (NOT executable — no shebang needed since it's sourced)
2. Define `cmd_<command>()` as the entry function accepting `"$@"`
3. Parse `--help` as the first argument → print usage with examples and exit 0
4. Use `mb_*` functions from `common.sh` (already sourced by dispatcher)
5. Use `mb_die` for fatal errors, `mb_warn` for warnings, `mb_success` for completion

### Help Text Format
From `bin/meetballs:13-30`, help text uses `cat <<'EOF'` heredoc. Each command's help should follow:
```
Usage: meetballs <command> [args...]

<description>

Options:
  --help    Show this help message

Examples:
  meetballs <command> <example args>
```

### Testing Pattern
From `tests/test_common.bats` and `tests/test_meetballs.bats`:
1. File: `tests/test_<command>.bats`
2. Load: `load test_helper`
3. Setup: use test_helper's setup (temp dirs + mock bin) or define custom setup that sources common.sh
4. Mock external commands with `create_mock_command "name" "body"`
5. Run commands with `run` and assert with `assert_success`, `assert_output --partial`, etc.
6. For testing via the dispatcher: `run "$BIN_DIR/meetballs" <command> <args>`
7. For testing module functions directly: source the module, then `run cmd_<command> <args>`

### Error Handling
- `mb_die "message"` for fatal errors (prints to stderr in red, exits 1)
- Validate inputs early (file existence, required arguments)
- Error messages should be actionable (include fix suggestions)

## Integration Points

### bin/meetballs → lib/<command>.sh
The dispatcher (`bin/meetballs:39-63`) already has `source` + `cmd_<command>` calls for all 5 commands. Creating the module files with the correct entry function is all that's needed — no dispatcher changes required.

### lib/common.sh utilities available to all modules
Key functions (from `lib/common.sh`):
- `mb_init` — Create `$RECORDINGS_DIR` and `$TRANSCRIPTS_DIR`
- `mb_detect_audio_backend` — Returns best backend name or exits 1
- `mb_check_command "cmd"` — Returns 0 if command exists, 1 if not
- `mb_check_disk_space` — Returns 0 if >=500MB, 1 if low (prints warning)
- `mb_format_duration $secs` — Outputs human-readable duration string
- `mb_timestamp` — Outputs `YYYY-MM-DDTHH-MM-SS`
- `$MEETBALLS_DIR`, `$RECORDINGS_DIR`, `$TRANSCRIPTS_DIR` — Directory constants
- `$WHISPER_MODEL` — Defaults to `base.en`
- `$MIN_DISK_MB` — 500

### External commands per module
| Module | External Commands | Mock Strategy |
|--------|------------------|---------------|
| doctor.sh | pw-record/parecord/arecord, whisper-cli, claude, df | `create_mock_command` to provide/omit each |
| list.sh | None (filesystem only) | Create fixture WAV files in `$RECORDINGS_DIR` |
| record.sh | pw-record/parecord/arecord | Mock recorder that creates a small WAV file |
| transcribe.sh | whisper-cli | Mock that creates `.txt` output file |
| ask.sh | claude | Mock that echoes response and logs args |

## Constraints for Builder

1. **`set -euo pipefail`** — already enforced by `bin/meetballs:2`. Module files are sourced into this context, so they inherit the setting. Do NOT add a separate `set -euo pipefail` in sourced module files.
2. **`MEETBALLS_DIR` override** — all paths must use `$RECORDINGS_DIR` / `$TRANSCRIPTS_DIR` constants (already set by common.sh), never hardcode `~/.meetballs`
3. **Colors disabled in pipes** — common.sh handles this at source time. Module code just calls `mb_info`, `mb_success`, etc.
4. **No system package installation** — `install.sh` and `doctor` must NOT install audio backends, whisper-cli, etc. Only report status and provide instructions.
5. **Error output to stderr** — use `mb_error`/`mb_warn`/`mb_die` which write to stderr
6. **WAV duration arithmetic** — `duration_secs = (file_size - 44) / (16000 * 2)` using `stat -c %s` and bash `$(( ))`. Integer seconds is sufficient.
7. **Claude CLI constraint** — `CLAUDECODE=1` env var blocks nested claude invocations. Tests must mock claude. Real invocation works for end users.
8. **Whisper model paths** — check `~/.local/share/whisper.cpp/models/`, `/usr/local/share/whisper.cpp/models/`, `$WHISPER_CPP_MODEL_DIR` for `ggml-${WHISPER_MODEL}.bin`
9. **Audio backend commands** — exact flags documented in `research/technologies.md` (pw-record, parecord, arecord each have different flag syntax)

## Implementation Order (from plan.md)

Remaining steps:
- Step 3: Doctor command (no deps on other commands)
- Step 4: List command (filesystem only)
- Step 5: Record command (SIGINT handling, backend detection)
- Step 6: Transcribe command (whisper-cli invocation)
- Step 7: Ask command (claude CLI, dual-mode)
- Step 8: Install script finalization

Each step has a corresponding task file in `specs/meetballs-cli/tasks/`.
