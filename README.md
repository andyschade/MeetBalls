# MeetBalls

```
         🍝  M E E T B A L L S  🍝
      Your meetings, locally digested.
```

MeetBalls is a local-first CLI tool that transcribes your meetings in real time and lets you ask questions while they're still happening. No cloud. No subscriptions. No one listening but your own machine.

You talk. [Whisper](https://github.com/ggml-org/whisper.cpp) listens. [Claude](https://docs.anthropic.com/en/docs/claude-code) answers.

## Why

- You're in a meeting and someone says a deadline. You missed it. Everyone's moved on.
- You recorded a meeting last week. The recording is 47 minutes long. You will never watch it.
- Your company wants you to use a transcription service that sends your audio to someone else's servers.

MeetBalls fixes all three. It runs entirely on your machine, costs nothing, and works in real time.

## What It Looks Like

```
$ meetballs live

┌─────────────────────────────────────────────────────┐
│ Starting live transcription... (Ctrl+C to stop)     │
│ Model: base.en                                      │
│ ---                                                 │
│ So the main thing we need to discuss today is the   │
│ deployment timeline. I think we should aim for next  │
│ Friday at the latest. The QA team needs at least    │
│ three days to run their regression suite.           │
│ ...                                                 │
├─────────────────────────────────────────────────────┤
│ > What deadline was mentioned?                      │
│ Based on the transcript, the deployment deadline    │
│ mentioned is next Friday.                           │
│                                                     │
│ >                                                   │
└─────────────────────────────────────────────────────┘
```

Top pane: live transcript, updating as people speak.
Bottom pane: ask questions about what's been said so far.

When you exit, the transcript and audio are saved to `~/.meetballs/`.

## Install

### Prerequisites

| Dependency | What it does | Install |
|---|---|---|
| **Bash 4.0+** | Runs everything | Pre-installed on most Linux systems |
| **[whisper.cpp](https://github.com/ggml-org/whisper.cpp)** | Speech-to-text engine | `git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp` |
| **[Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)** | AI Q&A against transcripts | See Anthropic docs |
| **tmux 3.4+** | Split-pane TUI for live mode | `sudo apt install tmux` |
| **libsdl2-dev** | Mic capture for live mode | `sudo apt install libsdl2-dev` |
| **Audio backend** | Records from your mic | PipeWire, PulseAudio, or ALSA (one of these is already on your system) |

### Setup

```bash
# Clone whisper.cpp and download a model
git clone https://github.com/ggml-org/whisper.cpp.git ~/whisper.cpp
cd ~/whisper.cpp && bash models/download-ggml-model.sh base.en

# Clone MeetBalls and install
git clone https://github.com/andyschade/MeetBalls.git
cd MeetBalls
./install.sh
```

The install script will:
- Set up the test framework
- Build `whisper-stream` from whisper.cpp (for live transcription)
- Verify the whisper model
- Symlink `meetballs` to `~/.local/bin/`
- Run `meetballs doctor` to check everything

### Verify

```bash
meetballs doctor
```

If everything shows `OK`, you're ready.

## Usage

### Live Mode (the main course)

```bash
meetballs live
```

Opens a tmux split-pane session. Speak into your mic and watch the transcript appear in real time. Ask questions in the bottom pane. Type `quit` or press Ctrl+C to end.

On exit, your transcript and audio are saved automatically.

### Post-Hoc Workflow (leftovers)

For when you want to record now, transcribe later:

```bash
# Record a meeting
meetballs record

# Transcribe the recording
meetballs transcribe ~/.meetballs/recordings/2026-02-13T10-00-00.wav

# Ask questions about it
meetballs ask ~/.meetballs/transcripts/2026-02-13T10-00-00.txt "What were the action items?"

# Or start an interactive session
meetballs ask ~/.meetballs/transcripts/2026-02-13T10-00-00.txt
```

### Other Commands

```bash
meetballs list       # Show all recordings and transcript status
meetballs update     # Pull latest code and check dependencies
meetballs doctor     # Check that everything is installed
meetballs --help     # Full usage
```

## How It Works

MeetBalls is ~900 lines of Bash, organized as:

```
bin/meetballs           Entry point — dispatches to command modules
lib/common.sh           Shared utilities (audio detection, paths, formatting)
lib/live.sh             Real-time transcription via whisper-stream + tmux
lib/record.sh           Audio recording via PipeWire/PulseAudio/ALSA
lib/transcribe.sh       Post-hoc transcription via whisper-cli
lib/ask.sh              Q&A via Claude Code CLI
lib/list.sh             Recording listing
lib/update.sh           Self-update via git
lib/doctor.sh           Dependency checker
```

**Live mode** creates a tmux session with two panes. The top pane runs `whisper-stream`, which captures mic audio via SDL2 and streams transcribed text in real time. The bottom pane runs an interactive loop that reads the growing transcript file and passes your questions to `claude` with the transcript as context.

All data stays in `~/.meetballs/`:

```
~/.meetballs/
├── recordings/     WAV files (16kHz, mono, 16-bit)
├── transcripts/    Plain text transcripts
└── live/           Temporary session data (cleaned up after each session)
```

## Platform Support

| Platform | Status |
|---|---|
| **Linux** (Ubuntu/Debian) | Supported |
| **WSL2** | Supported (with WSLg audio) |
| **macOS** | Not supported (audio backend differences) |
| **Windows** | Not supported |

## Configuration

MeetBalls respects these environment variables:

| Variable | Default | Description |
|---|---|---|
| `MEETBALLS_DIR` | `~/.meetballs` | Base data directory |
| `WHISPER_MODEL` | `base.en` | Whisper model name |
| `WHISPER_CPP_DIR` | `~/whisper.cpp` | Path to whisper.cpp source |
| `WHISPER_CPP_MODEL_DIR` | — | Override model search path |
| `WHISPER_CPP_COMMIT` | — | Pin whisper.cpp to a specific commit for builds |

## Uninstall

```bash
./install.sh --uninstall
```

Removes the symlink and install state. Optionally removes your meeting data. System packages (tmux, SDL2, etc.) are left alone.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
