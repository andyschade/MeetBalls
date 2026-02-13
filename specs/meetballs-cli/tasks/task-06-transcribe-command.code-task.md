---
status: completed
created: 2026-02-12
started: 2026-02-13
completed: 2026-02-13
---
# Task: Transcribe Command + Tests (TDD)

## Description
Implement the `meetballs transcribe` command that takes a recording WAV file, invokes whisper-cli to transcribe it offline, and saves the transcript as a plain text file. Includes input validation, model detection, and progress output.

## Background
The transcribe command bridges recording and Q&A. It validates the input file, finds the whisper model, invokes `whisper-cli` with the correct flags, and outputs the transcript to the transcripts directory. The output filename matches the recording basename with a `.txt` extension for easy pairing.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.4 — Transcription)

**Additional References:**
- specs/meetballs-cli/context.md (whisper-cli flags, model paths)
- specs/meetballs-cli/plan.md (test_transcribe.bats test cases)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Entry function: `cmd_transcribe "$@"`
2. Handle `--help` flag — print usage with description and examples, exit 0
3. Validate argument: recording file path must be provided and file must exist
4. Check `whisper-cli` is available via `mb_check_command` — die with install URL if not
5. Check whisper model exists — search in:
   - `$WHISPER_CPP_MODEL_DIR/ggml-${WHISPER_MODEL}.bin`
   - `~/.local/share/whisper.cpp/models/ggml-${WHISPER_MODEL}.bin`
   - `/usr/local/share/whisper.cpp/models/ggml-${WHISPER_MODEL}.bin`
6. Die with download instructions if model not found
7. Warn if recording >2 hours (duration > 7200 seconds from WAV header)
8. Determine output path: `$TRANSCRIPTS_DIR/<basename-without-ext>.txt`
9. Invoke whisper-cli:
   ```bash
   whisper-cli -m "$model_path" -f "$recording_file" --output-txt --output-file "$transcript_base" --print-progress
   ```
10. Print transcript path on completion

## Dependencies
- Task 01 (common.sh: `mb_check_command`, path helpers, `mb_format_duration`)
- Task 02 (CLI dispatcher routes `transcribe` to this module)

## Implementation Approach
1. **RED**: Write `tests/test_transcribe.bats` with all test cases
2. **GREEN**: Implement `lib/transcribe.sh` with `cmd_transcribe` function
3. **REFACTOR**: Clean up error messages and model search logic

### Test cases (from plan):
- `--help` prints usage containing "Usage" and "transcribe", exit 0
- Errors on missing argument (no args) → stderr contains error, exit 1
- Errors on nonexistent file (fake path) → stderr contains "not found" or similar, exit 1
- Errors when whisper-cli missing (no mock whisper-cli) → stderr contains error, exit 1
- Successful transcription (mock whisper-cli creates .txt) → transcript file exists in transcripts dir
- Output path printed → stdout contains transcript path
- Handles empty output (mock whisper-cli creates empty .txt) → exit 0, no error

### Mock strategy:
- Mock `whisper-cli` as a script that:
  - Parses `--output-txt` and `--output-file` flags
  - Creates `<output-file>.txt` with sample text (or empty for empty test)
  - Exits 0
- Create fixture WAV files in `$MEETBALLS_DIR/recordings/` for input

## Acceptance Criteria

1. **Help flag**
   - Given the user runs `meetballs transcribe --help`
   - When output is examined
   - Then it contains "Usage" and "transcribe" and exits 0

2. **Missing argument error**
   - Given no arguments are provided
   - When running `meetballs transcribe`
   - Then stderr contains an error and exits 1

3. **Nonexistent file error**
   - Given a path to a file that doesn't exist
   - When running `meetballs transcribe /fake/path.wav`
   - Then stderr contains a "not found" error and exits 1

4. **Missing whisper-cli error**
   - Given whisper-cli is not on PATH
   - When running `meetballs transcribe <valid-file>`
   - Then stderr contains an error with install instructions and exits 1

5. **Successful transcription**
   - Given a valid WAV file and mock whisper-cli
   - When running `meetballs transcribe <file>`
   - Then a `.txt` file exists in the transcripts directory

6. **Transcript path printed**
   - Given a successful transcription
   - When examining stdout
   - Then it contains the path to the transcript file

7. **Empty output handled gracefully**
   - Given whisper-cli produces an empty transcript
   - When running `meetballs transcribe`
   - Then it exits 0 without error

8. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_transcribe.bats`
   - Then all tests pass

## Metadata
- **Complexity**: Medium
- **Labels**: command, transcribe, whisper
- **Required Skills**: Bash, bats-core testing, PATH mocking
