# Technologies — MeetBalls Live

## Available in Codebase

### whisper-stream
- Built from whisper.cpp's `examples/stream/` directory
- Requires `-DWHISPER_SDL2=ON` at build time
- Requires `libsdl2-dev` system package
- Key flags: `-m <model>`, `--step 3000`, `--length 10000`, `--no-timestamps`, `-f <file>`, `--save-audio`, `-l en`
- `--save-audio` produces 16kHz mono 16-bit PCM WAV (identical to `meetballs record` format)
- WAV filename: `output_YYYYMMDDhhmmss.wav` in CWD

### claude CLI
- Claude Code CLI, invoked as `claude`
- Single-shot mode: `claude -p "<prompt>" --append-system-prompt "<system prompt>"`
- Interactive mode: `claude --append-system-prompt "<system prompt>"`
- Used in `lib/ask.sh:56` for single-shot and `lib/ask.sh:59` for interactive

### tmux
- Terminal multiplexer for split-pane TUI
- Key commands needed:
  - `tmux new-session -d -s <name>` — create detached session
  - `tmux split-window -v -p <percent> -t <session>` — vertical split
  - `tmux send-keys -t <session>:<pane> '<cmd>' Enter` — execute in pane
  - `tmux attach-session -t <name>` — attach (blocks)
  - `tmux kill-session -t <name>` — kill session
  - `tmux has-session -t <name>` — check if session exists

### whisper-cli
- Post-hoc transcription (not real-time)
- Used by `meetballs transcribe` — distinct from `whisper-stream`

### bats-core
- Test framework in `tests/libs/bats/`
- Extensions: bats-support, bats-assert
- Run: `./tests/libs/bats/bin/bats tests/`

## System Dependencies

### libsdl2-dev
- Required by whisper-stream for microphone capture
- Check: `dpkg -s libsdl2-dev 2>/dev/null | grep -q "ok installed"`
- Install: `sudo apt install libsdl2-dev`

### Audio backends (existing)
- PipeWire (`pw-record`), PulseAudio (`parecord`), ALSA (`arecord`)
- Detected by `mb_detect_audio_backend()` in `lib/common.sh:72-82`
- Used by `meetballs record` — NOT by `meetballs live` (whisper-stream handles its own audio via SDL2)
