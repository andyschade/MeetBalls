---
status: completed
created: 2026-02-13
started: 2026-02-13
completed: 2026-02-13
---
# Task: Add whisper-stream build step to `install.sh`

## Description
Add a new section to `install.sh` that builds `whisper-stream` from the whisper.cpp source with SDL2 support. This is non-fatal — if the source isn't found, it prints instructions and skips.

## Background
`whisper-stream` is built from whisper.cpp's `examples/stream/` directory and requires SDL2 for microphone capture. The install script needs to handle: checking if already installed, checking for SDL2, locating whisper.cpp source, building, and copying the binary.

## Reference Documentation
**Required:**
- Design: specs/meetballs-live/design.md (Section 4.8)

**Additional References:**
- specs/meetballs-live/plan.md (Step 6)
- specs/meetballs-live/context.md (Integration Point 6)

**Note:** You MUST read the design document before beginning implementation.

## Technical Requirements
1. Insert new section between bats install (step 2) and symlink creation (step 3)
2. Check if `whisper-stream` is already on PATH — skip if found
3. Check `dpkg -s libsdl2-dev 2>/dev/null` — if missing, prompt: `libsdl2-dev not found. Install it? [Y/n]`
4. Locate whisper.cpp source in order:
   - `$WHISPER_CPP_DIR` (environment variable)
   - `$HOME/whisper.cpp`
   - `/usr/local/src/whisper.cpp`
5. Build: `cmake -B build -DWHISPER_SDL2=ON && cmake --build build --target stream`
6. Copy binary: `sudo cp build/bin/stream /usr/local/bin/whisper-stream`
7. If whisper.cpp source not found: print instructions and skip (non-fatal)
8. Renumber subsequent steps if needed

## Dependencies
- None (independent of other tasks, no code dependencies)

## Implementation Approach
1. Read current `install.sh` to understand section numbering and style
2. Add the new section following existing formatting conventions
3. **VERIFY**: Run `tests/test_install.bats` — all existing tests pass (regression-only)

## Acceptance Criteria

1. **Skip if already installed**
   - Given `whisper-stream` is already on PATH
   - When `install.sh` runs the new section
   - Then it prints a skip message and moves on

2. **SDL2 check with prompt**
   - Given `libsdl2-dev` is not installed
   - When the build step runs
   - Then it prompts the user to install it

3. **Source location search**
   - Given whisper.cpp source exists at `$HOME/whisper.cpp`
   - When the build step runs
   - Then it finds and uses that directory

4. **Non-fatal on missing source**
   - Given whisper.cpp source is not found anywhere
   - When the build step runs
   - Then it prints instructions and continues (does not exit 1)

5. **Build commands correct**
   - Given whisper.cpp source is found and SDL2 is available
   - When the build step runs
   - Then it uses `cmake -B build -DWHISPER_SDL2=ON` and targets `stream`

6. **No regressions**
   - Given the changes are complete
   - When running `tests/test_install.bats`
   - Then all existing tests pass

## Metadata
- **Complexity**: Low
- **Labels**: install, whisper-stream, sdl2
- **Required Skills**: Bash, cmake
