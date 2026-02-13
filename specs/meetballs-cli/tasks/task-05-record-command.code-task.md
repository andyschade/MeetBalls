---
status: completed
created: 2026-02-12
started: 2026-02-12
completed: 2026-02-12
---
# Task: Record Command + Tests (TDD)

## Description
Implement the `meetballs record` command that detects the available audio backend, starts recording to a WAV file, handles SIGINT for graceful stop, and prints the recording duration and file path on completion.

## Background
The record command is the primary entry point for capturing meeting audio. It auto-detects the best available audio backend (PipeWire > PulseAudio > ALSA), generates a timestamp-based filename, starts recording in the background, and uses a SIGINT trap to stop gracefully. Duration is computed from WAV header arithmetic.

## Reference Documentation
**Required:**
- Design: specs/meetballs-cli/design.md (Section 3.3 — Recording)

**Additional References:**
- specs/meetballs-cli/context.md (audio backend flags, WAV header arithmetic)
- specs/meetballs-cli/plan.md (test_record.bats test cases)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Entry function: `cmd_record "$@"`
2. Handle `--help` flag — print usage with description and examples, exit 0
3. Call `mb_init` to ensure directories exist
4. Call `mb_check_disk_space` — warn if low
5. Call `mb_detect_audio_backend` — die if no backend found
6. Generate output filename: `$(mb_timestamp).wav` in `$RECORDINGS_DIR`
7. Start the audio backend in the background with correct flags per backend:
   - PipeWire: `pw-record --rate=16000 --channels=1 --format=s16 "$output_file"`
   - PulseAudio: `parecord --rate=16000 --channels=1 --format=s16le --file-format=wav "$output_file"`
   - ALSA: `arecord -f S16_LE -r 16000 -c 1 -t wav "$output_file"`
8. Print `Recording... (press Ctrl+C to stop)`
9. Set SIGINT trap: kill recorder PID, wait, compute duration, print summary
10. Compute duration from WAV: `(file_size - 44) / (16000 * 2)` seconds
11. Print: `Saved: <path> (duration: <formatted>)`

## Dependencies
- Task 01 (common.sh: `mb_init`, `mb_detect_audio_backend`, `mb_timestamp`, `mb_format_duration`, `mb_check_disk_space`)
- Task 02 (CLI dispatcher routes `record` to this module)

## Implementation Approach
1. **RED**: Write `tests/test_record.bats` with all test cases
2. **GREEN**: Implement `lib/record.sh` with `cmd_record` function
3. **REFACTOR**: Ensure clean trap handling and error messages

### Test cases (from plan):
- `--help` prints usage containing "Usage" and "record", exit 0
- Errors when no audio backend (no mocked backends) → stderr contains error, exit 1
- Starts and stops recording (mock pw-record that creates WAV on SIGTERM) → output file exists, success message printed
- Output file named with timestamp → filename matches `YYYY-MM-DDTHH-MM-SS.wav`
- Prints duration on completion → mock pw-record creates known-size WAV, output contains formatted duration
- Warns on low disk space → mock `df` returning low space, stderr contains warning

### Mock strategy:
- Mock the audio backend (e.g., `pw-record`) as a script that:
  - Creates a valid WAV file (44-byte header + known PCM data) at the specified path
  - Traps SIGTERM to exit cleanly (simulating Ctrl+C stop)
  - Sleeps until killed (simulating ongoing recording)
- Send SIGINT or SIGTERM to the `meetballs record` process during test to trigger stop

## Acceptance Criteria

1. **Help flag**
   - Given the user runs `meetballs record --help`
   - When output is examined
   - Then it contains "Usage" and "record" and exits 0

2. **No audio backend error**
   - Given no audio backends are available
   - When running `meetballs record`
   - Then stderr contains an error about missing audio backend and exits 1

3. **Successful recording with mock**
   - Given a mock audio backend is available
   - When `meetballs record` is started and then stopped
   - Then a WAV file exists in the recordings directory and a success message is printed

4. **Timestamp-based filename**
   - Given a successful recording
   - When examining the output filename
   - Then it matches the `YYYY-MM-DDTHH-MM-SS.wav` pattern

5. **Duration printed**
   - Given a mock recording creates a known-size WAV file
   - When the recording is stopped
   - Then the printed duration matches the expected formatted value

6. **Low disk space warning**
   - Given disk space is below 500MB
   - When running `meetballs record`
   - Then stderr contains a warning about low disk space

7. **Tests pass**
   - Given the implementation is complete
   - When running `./tests/libs/bats/bin/bats tests/test_record.bats`
   - Then all tests pass

## Metadata
- **Complexity**: High
- **Labels**: command, record, audio, signals
- **Required Skills**: Bash, signal handling, background processes, bats-core testing
