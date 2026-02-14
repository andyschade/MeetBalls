# MeetBalls — Intelligent Meeting Facilitation, Storage Restructure & History

## Problem Statement

MeetBalls currently transcribes meetings and lets users ask questions manually. But
it's passive — a dumb recorder. Meetings need an intelligent facilitator that can
track speakers, capture agendas, log decisions, research questions, and produce
wrap-up summaries — all autonomously, with minimal distraction to humans.

Additionally, the storage structure scatters session artifacts across separate
directories, making it hard to think of a meeting as a single session. And
`meetballs list` only shows raw file info with no summaries or interactivity.

## What To Build

An intelligent facilitation layer on top of `meetballs live` plus a storage
restructure and new commands:

1. **Hat System** — contextual roles MeetBalls wears during different meeting phases
2. **Mute/Unmute State** — orthogonal to hats, controls whether MeetBalls can vocalize
3. **Wake Word Detection** — "meetballs" keyword triggers hat invocations, state changes
4. **Autonomous Q&A Pane** — MeetBalls uses the Q&A pane sparingly for its own needs
5. **Storage Restructure** — per-session folders with descriptive names
6. **`meetballs hist`** — interactive history browser replacing `meetballs list`
7. **`meetballs clean`** — remove recordings to reclaim disk space
8. **Speaker Diarization & Tagging** — three-tier speaker identification with graceful fallback

## Existing Codebase

`meetballs live` is fully implemented with passing tests. Key files:

- `bin/meetballs` — CLI dispatcher (routes to subcommands)
- `lib/live.sh` — tmux split-pane TUI (top: transcript, bottom: Q&A)
- `lib/common.sh` — shared utilities (colors, paths, audio detection, formatting)
- `lib/ask.sh` — Q&A via claude CLI with transcript as system prompt
- `lib/list.sh` — current list command (to be replaced by hist)
- `lib/record.sh` — audio recording
- `lib/transcribe.sh` — post-hoc transcription
- `lib/logs.sh` — log viewing
- `lib/doctor.sh` — dependency checker
- `tests/` — bats-core test suite

**DO NOT rewrite or break the existing code.** Build on top of it.

**Leave `record` and `transcribe` commands unchanged** — they use the old
`recordings/` and `transcripts/` paths and are standalone utilities unrelated
to the session folder structure.

---

## Feature 1: Hat System

### Design Principles

- Hats define *what MeetBalls is doing* during the meeting
- Hat transitions are driven by the **two-stage pipeline** (transcript analysis)
  or explicit wake word — never by timers
- Users can override via wake word: "meetballs [hat-name]"
- The hatless default state is called **Listener**

### Hat Lifecycle

```
Listener (default, always active) ──("meetballs wrap-up")──► Wrap-up
```

### Listener (default state — always active)

MeetBalls starts in Listener mode when `meetballs live` begins. All Stage 1
triggers are active from the start — intro/agenda patterns, action-item triggers,
decision triggers, wake word detection all run simultaneously.

- Always organizes transcript by speaker and conversation flow
- Transcript tagged with speaker names (see Feature 8: Speaker Diarization & Tagging)

#### Initialization Concern: Speakers & Agenda

At the start of a meeting, Listener has an unresolved concern — it doesn't yet
know who's in the meeting or what the agenda is.

- **Stage 1 triggers** for initialization (run alongside all other triggers):
  - Introduction patterns: "Hi I'm...", "My name is...", "Nice to meet you"
  - Agenda patterns: "Today we're going to discuss...", "The agenda is...",
    "Let's cover..."
  - New proper nouns / names appearing
- **Stage 2** (Haiku): when triggers fire, extracts speaker names and agenda items,
  updates `session-state.md`
- **Surfaces**: speaker list and agenda in Q&A pane once captured
- Once both speakers and agenda are confirmed, the initialization concern is
  marked done — these triggers stop firing, everything else continues unchanged
- If MeetBalls can't identify a speaker or missed the agenda, it sends a transient
  pop-up in the Q&A pane: "Could you reintroduce the third speaker?" or "Could you
  restate the agenda?"

#### Passive Hats (always running in background during Listener)

- **Action-Item Tracker** — detects commitments ("I'll do X by Friday"), captures
  action items with owners and deadlines. Surfaces each detection in Q&A pane
  as it happens and logs to `session-state.md`.
- **Decision Logger** — detects consensus or explicit decisions, logs with context.
  Surfaces each detection in Q&A pane as it happens and logs to `session-state.md`.

#### Active Hats (invoked one at a time via wake word or MeetBalls inference)

- **Researcher** — hears a question nobody answers, or explicit "meetballs research
  [topic]". Goes off to research, returns with citation references linked to sources.
  Shows research progress in Q&A pane. Citations appear contextually in transcript.
- **Fact-Checker** — hears a factual claim that sounds uncertain. Quietly verifies,
  surfaces correction if wrong.
- **Timekeeper** — if agenda items have time bounds, nudges via Q&A pop-up when
  running over.

Active hats are mutually exclusive — one at a time. New invocation replaces current.

### Wrap-up Hat (explicitly triggered: "meetballs wrap-up")

- Triggered ONLY by wake word, never auto-inferred
- **Produces** (rendered in Q&A pane):
  - Meeting summary
  - List of decisions made (from Decision Logger)
  - Action items with owners and deadlines (from Action-Item Tracker)
  - Unresolved questions
- Ends the facilitation session

---

## Feature 2: Mute / Unmute State

- **Orthogonal to hats** — state applies regardless of which hat is active
- **Mute (default)**: MeetBalls operates silently. All output goes to Q&A pane/screen
  only. No voice interjection.
- **Unmute**: MeetBalls can interject with voice when it has something to contribute
  (research complete, fact-check result, time warning, etc.)
- **Toggle via wake word**: "meetballs unmute" / "meetballs mute"
- MeetBalls always starts in mute state

---

## Feature 3: Wake Word System

- **Wake word**: "meetballs"
- After detecting wake word in transcript, parse proximity for:
  - **Hat names**: "research", "fact-check", "wrap-up", etc.
  - **State changes**: "mute", "unmute"
  - **Actions**: "research [topic]", "interject"
- Examples:
  - "meetballs research what's the latest on that API deprecation"
  - "meetballs wrap-up"
  - "meetballs unmute"
  - "meetballs mute"
- If MeetBalls detects wake word but can't infer intent, it sends a transient pop-up:
  "What hat would you like me to wear for this task?"

---

## Feature 4: Q&A Pane Behavior

- MeetBalls uses the Q&A pane **consciously and sparingly** — assist, don't distract
- **User queries**: still works as before — user types questions, gets answers
- **MeetBalls-initiated**: transient pop-up messages for clarification only when
  MeetBalls cannot infer the answer:
  - "Could you reintroduce the third speaker?"
  - "Could you restate the agenda?"
  - "What hat would you like me to wear for this task?"
- MeetBalls listens for responses to its pop-ups in **both** the transcript and the
  Q&A input window
- Research progress and results display in Q&A pane with citation references

---

## Feature 5: Storage Restructure

### Current Structure (to be migrated)

Artifacts scattered across separate directories:
```
~/.meetballs/
  transcripts/<timestamp>.txt
  recordings/<timestamp>.wav
  logs/<timestamp>.qa.log
  logs/<timestamp>.log
```

### New Structure: Per-Session Folders

Each meeting is a self-contained session folder:
```
~/.meetballs/sessions/<session-name>/
  transcript.txt       # speaker-tagged transcript
  recording.wav        # audio recording (removable via 'clean')
  qa.log               # Q&A interactions
  summary.txt          # LLM-generated meeting summary
  session-state.md     # structured state (see below)
  session.log          # diagnostic log
```

### Session State File (`session-state.md`)

Markdown format — easiest for Claude CLI to read/write reliably:

```markdown
# Session State

## Hat
listener

## Muted
true

## Speakers
- Andy
- Sarah

## Agenda
- Deployment timeline
- QA handoff

## Action Items
- [ ] Sarah: QA signoff checklist (by Wednesday)

## Decisions
- Freeze feature branches Wednesday — give QA 3 days for regression

## Research
(none)

## Duration
47 min
```

- Updated during the meeting by the background processing pipeline
- Read by Wrap-up hat to produce final summary
- Read by `hist` for participants and duration (survives `clean` deleting recordings)
- Duration is calculated from recording and cached here at session end

### Session Naming Convention

Format: `<date>-<year>-<time>-<participants>-<topic>/`

- Date: `feb14` (lowercase month abbreviation + day)
- Year: `26` (two-digit year)
- Time: `0800` (24-hour, no separator)
- Participants: `andy-sarah` (lowercase, hyphen-separated)
- Topic: up to 5 words, slugified (e.g., `deployment-timeline-qa-handoff`)

Participants do NOT count toward the 5-word topic limit.

Examples:
```
feb14-26-0800-andy-sarah-deployment-timeline-qa-handoff/
feb13-26-1430-andy-sarah-mike-api-redesign-v2-migration/
feb10-26-1000-andy-sarah-sprint-retro-process-improvements/
```

The topic description and participant names are LLM-generated from the transcript
at session end (same time the summary is generated).

### Temporary Session Directory

During a live meeting, artifacts are stored in `~/.meetballs/live/<timestamp>/`
(the existing temp directory). At session end, after the LLM generates the
descriptive session name, the folder is renamed and moved to its final location
at `~/.meetballs/sessions/<session-name>/`.

### Default Save (`~/.meetballs/sessions/`)

Every meeting always saves to `~/.meetballs/sessions/<session-name>/`.

### `--save-here` (CWD copy)

When `--save-here` is used, the session folder is **also** copied to
`./meetballs/<session-name>/` in the current working directory. Both copies use
the same naming convention. The `~/.meetballs/sessions/` copy is always canonical.

### Migration

- Update `lib/live.sh` cleanup to save to new per-session folder structure
- Update `lib/live.sh` `--save-here` to copy session folder to CWD
- No backward compatibility with old scattered file structure — legacy files
  will be cleared manually

---

## Feature 6: `meetballs hist` (replaces `meetballs list`)

### Purpose

Interactive history browser that replaces the current `meetballs list` command.

### Interface

```
$ meetballs hist

 MEETBALLS HISTORY                                    3 sessions

 ▸ ┌ [1] Feb 14, 2026 · 8:00 AM · 47 min
   │ Andy, Sarah
   │ Discussed pushing deployment to next Friday. Agreed to
   │ freeze feature branches Wed. Sarah owns QA signoff.
   └ ~/.meetballs/sessions/feb14-26-0800-andy-sarah-deployment-timeline-qa-handoff/

   ┌ [2] Feb 13, 2026 · 2:30 PM · 1h 12 min
   │ Andy, Sarah, Mike
   │ Walked through v2 API migration. Decided to deprecate
   │ /users with 6-month sunset. Mike raised mobile compat.
   └ ~/.meetballs/sessions/feb13-26-1430-andy-sarah-mike-api-redesign-v2-migration/

   ┌ [3] Feb 10, 2026 · 10:00 AM · 32 min
   │ Andy, Sarah
   │ Sprint retro. Main pain point was flaky CI. Agreed to
   │ dedicate two days next sprint to test stability.
   └ ~/.meetballs/sessions/feb10-26-1000-andy-sarah-sprint-retro-process-improvements/

 ↑↓ navigate · enter select · q quit
```

### Visual Design

- `▸` marks the highlighted/selected entry (green)
- Header line: bold cyan — date, time, duration
- Participants: dim
- Summary: normal text, 3-4 sentences summarizing what was discussed, decided, and
  who owns what (NOT just the folder name reworded — a real brief of the transcript)
- Path: dim
- Box-drawing characters (`┌ │ └`) for card-style visual separation
- Footer: `↑↓ navigate · enter select · q quit`
- Title bar shows total session count

### Interaction

- `meetballs hist --help` shows usage
- `↑`/`↓` or `j`/`k` to navigate between sessions
- `enter` to select — opens a **new tmux window** with PWD set to the session folder
  - Inside tmux: `tmux new-window -c "$selected_path" -n "meetball"`
  - Outside tmux: `tmux new-session -d -s meetball-hist -c "$selected_path"` then attach
- `q` to quit

### Summary Generation

- Summary is LLM-generated via `claude` CLI from the transcript at session end
- Cached as `summary.txt` inside the session folder
- If no cached summary exists, generate on first `hist` call

### Empty State

When no sessions exist:
```
$ meetballs hist

 MEETBALLS HISTORY                                    0 sessions

 No sessions found. Run 'meetballs live' to start your first meeting.
```

### Replaces `meetballs list`

- Remove `list` command from dispatcher, help text, and tests
- Add `hist` command in its place
- `meetballs list` should print a deprecation notice pointing to `meetballs hist`

---

## Feature 7: `meetballs clean`

### Purpose

Remove audio recordings from `~/.meetballs/sessions/` to reclaim disk space.

### Behavior

1. `meetballs clean --help` shows usage
2. Scan `~/.meetballs/sessions/*/recording.wav` for all recordings
3. List each recording with its session name and file size
4. Show total space that would be reclaimed
5. Prompt for confirmation
6. On confirm: delete only the `recording.wav` files (all other session artifacts preserved)

### Empty State

When no recordings exist:
```
$ meetballs clean

No recordings found in ~/.meetballs/sessions/.
```

### Scope

- Only touches `~/.meetballs/sessions/` — never touches `--save-here` CWD copies
- CWD copies are the user's responsibility to manage

---

## Feature 8: Speaker Diarization & Transcript Tagging

### Transcript Format

Speaker-tagged chat-style format:
```
[Andy] So the deadline is next Friday at the latest.
[Sarah] The QA team needs at least three days for regression.
[Andy] Right, so we freeze feature branches Wednesday.
[Unknown] What about the staging environment?
```

- Tag with best-guess speaker when confident
- Use `[Unknown]` when not confident
- Speaker names come from Listener initialization

### Three-Tier Diarization (graceful degradation)

1. **`--tinydiarize` (try first)** — whisper.cpp built-in experimental diarization.
   Zero new dependencies. Enabled by adding `--tinydiarize` flag to whisper-stream.
   Provides speaker change markers in the transcript stream.

2. **pyannote-audio (if installed)** — Python-based speaker diarization. More accurate
   than tinydiarize. Runs as a sidecar process analyzing the audio stream, outputs
   speaker segments. MeetBalls pairs these with whisper's transcript to tag lines.
   Optional dependency — not required.

3. **LLM post-process (fallback, always works)** — At session end, send the complete
   raw transcript + speaker list from Listener initialization to Sonnet. One LLM call produces
   the full speaker-tagged `transcript.txt`. Uses full conversation context (who
   responded to whom, name mentions, speaking patterns) for best inference.

MeetBalls uses the best available tier automatically.

### `meetballs doctor` Integration

```
Speaker diarization:
  ✓ whisper tinydiarize        available (built-in)
  ✗ pyannote-audio             not installed
    ℹ For better speaker diarization, install pyannote-audio
      (recommended: 8GB+ RAM, dedicated GPU)
      pip install pyannote.audio
```

- Doctor reports which tiers are available
- Suggests pyannote-audio on systems with sufficient resources (8GB+ RAM, GPU)

### Real-Time vs Post-Process

- **tinydiarize / pyannote**: can tag speakers in real-time during the meeting
- **LLM fallback**: post-process only — tags the full transcript at session end
- During the meeting with LLM fallback, transcript is untagged. Passive hats
  (action items, decisions) still work on untagged text via keyword triggers.
  The Stage 2 Haiku refinement call can infer speaker from surrounding context.

---

## Architecture: Two-Stage Background Processing Pipeline

### Problem

The hat system requires MeetBalls to continuously analyze the transcript during the
meeting. Calling an LLM on every new line would burn excessive tokens.

### Solution: Bash Triggers → LLM Refinement

```
Transcript lines (new)
      │
      ▼
  Stage 1: Bash pattern matching (every new line, free)
      │
      ├── nothing interesting → skip
      │
      └── trigger detected → Stage 2: LLM call (costs tokens)
```

**Stage 1 (bash, free)** — runs on every new transcript line:
- Wake word detection: `grep -i "meetballs"` — pure string match
- Action-item triggers: "I'll", "I will", "by Friday", "take that on", "deadline"
- Decision triggers: "agreed", "decided", "let's go with", "consensus", "final answer"
- Speaker name mentions for tagging (after Listener initialization identifies names)

**Stage 2 (LLM, costs tokens)** — only runs when Stage 1 flags something:
- Refine and structure detected action items with owner/deadline
- Extract what was actually decided from context
- Handle wake word commands (parse intent)
- Update `session-state.md`

### Model Tiering

| Task | Model | Why |
|---|---|---|
| Wake word detection | **None** — bash string matching | Free, instant |
| Speaker tagging, state updates | **Haiku** | Fast, cheap, runs on triggers |
| Action item / decision extraction | **Haiku** | Pattern recognition, not deep reasoning |
| Research | **Sonnet** | Needs quality reasoning and synthesis |
| Fact-checking | **Sonnet** | Needs accuracy |
| Wrap-up summary | **Sonnet** | Needs to produce a coherent brief |
| Session naming + summary generation | **Sonnet** | One-time call at session end |
| Speaker tagging post-process (fallback) | **Sonnet** | Full transcript context needed |

### Implementation Details

#### Reading New Lines

whisper-stream appends text to `transcript.txt`. A background bash process uses
`tail -f` on that file:

```bash
tail -f "$SESSION_DIR/transcript.txt" | while IFS= read -r line; do
    # Stage 1: pattern match on $line
done
```

Every new line whisper outputs gets checked immediately. No polling interval.

#### Stage 2 Context Window

The LLM needs context, but sending the entire growing transcript every time is
wasteful. Instead:

```
Stage 2 input = session-state.md + last ~20 lines of transcript + triggered line
```

- **`session-state.md`**: accumulated knowledge (speakers, agenda, action items,
  decisions). This is the LLM's "memory" — it doesn't need the full transcript
  because the important stuff is already extracted here.
- **Last ~20 lines**: recent conversational context around the trigger, so the LLM
  can understand who said what and what they were responding to.
- **Triggered line**: the specific line that fired Stage 1.

This keeps token cost roughly constant per call regardless of meeting length.

#### LLM Output

The LLM returns the updated `session-state.md`. System prompt:

```
You are MeetBalls, a meeting assistant. Given the current session state
and recent transcript context, analyze the triggered line and update
the session state. Only modify sections that need updating.

Triggered by: [action-item / decision / wake-word / initialization]
```

Bash writes the updated state back to disk.

#### Batching

If one line fires multiple triggers (e.g., "I'll handle the deployment by Friday,
and we've agreed on the timeline" hits both action-item AND decision), they're
batched into a single LLM call — one call, not two.

#### Full Flow Example

```
whisper outputs: "I'll get the QA checklist done by Wednesday"
      │
      ▼
tail -f reads the line
      │
      ▼
Stage 1: matches "I'll" → action-item trigger
      │
      ▼
Stage 2: build prompt
  ├── read session-state.md
  ├── read last 20 lines of transcript.txt
  └── include triggered line + trigger type
      │
      ▼
claude -p --model haiku "<prompt>"
      │
      ▼
write updated session-state.md back to disk
      │
      ▼
surface new action item in Q&A pane
```

---

## Technical Constraints

- **Language**: Bash shell scripts (primary), with Claude CLI for LLM calls
- **No paid transcription/cloud services**: Transcription is local via whisper.
  LLM calls use `claude` CLI (Claude Code) which costs tokens — the two-stage
  pipeline minimizes this cost.
- **Claude CLI**: Uses `claude` CLI command (Claude Code) with `--model` flag for
  model tiering (e.g., `claude -p --model haiku`, `claude -p --model sonnet`)
- **TUI**: tmux (existing split-pane setup)
- **Platform**: Linux / WSL2
- **TTS for unmute**: Flag the integration point but do not implement actual audio
  output / text-to-speech. The unmute state should control the *intent* to speak;
  actual voice synthesis is a future feature.

## Non-Goals (Explicitly Out of Scope)

- Actual TTS/voice synthesis for unmute mode
- Full pyannote-audio sidecar integration (detect and suggest in doctor, but actual
  audio pipeline integration is future work — only tinydiarize and LLM fallback
  are implemented)
- Web UI or GUI
- Cloud storage or sync
- macOS / Windows native support

## Changes Required

### `lib/live.sh` — Modify
- Integrate hat system into the live session loop
- Add wake word detection in transcript processing
- Add mute/unmute state management
- Add two-stage background processing pipeline (bash triggers → LLM refinement)
- Enable `--tinydiarize` flag on whisper-stream
- Speaker tagging: real-time if tinydiarize/pyannote available, LLM post-process fallback
- Update cleanup to save to per-session folder structure
- Generate session name (participants + topic) via LLM at session end
- Generate summary.txt via LLM at session end
- Update `--save-here` to copy session folder to CWD

### `lib/hist.sh` — New file
- Interactive history browser TUI
- Scan `~/.meetballs/sessions/` for sessions
- Parse session folder names for metadata
- Read cached `summary.txt` for display
- Arrow key / vim-key navigation
- tmux new-window on selection

### `lib/clean.sh` — New file
- Scan for recordings, display with sizes
- Confirm and delete

### `lib/list.sh` — Deprecate
- Replace with deprecation notice pointing to `meetballs hist`

### `lib/doctor.sh` — Update
- Add diarization tier reporting (tinydiarize available? pyannote installed?)
- Suggest pyannote-audio on systems with sufficient resources (8GB+ RAM, GPU)

### `bin/meetballs` — Update dispatcher
- Add `hist` and `clean` commands
- Update help text
- Deprecate `list`

### `lib/common.sh` — Add shared helpers
- Session folder naming utilities
- Session scanning/discovery functions
- Diarization tier detection (tinydiarize available? pyannote installed?)

### Tests — Update and add
- `tests/test_hist.bats` — new tests for hist command
- `tests/test_clean.bats` — new tests for clean command
- `tests/test_live.bats` — update for new storage structure and hat system
- `tests/test_meetballs.bats` — update dispatcher tests
- All existing tests must continue to pass

## Success Criteria

1. Listener captures speakers and agenda at meeting start, surfaces in Q&A pane
2. Listener organizes transcript by speaker with passive hats always running
3. Active hats invocable via "meetballs [hat-name]" wake word
4. Researcher returns results with citations in transcript
5. "meetballs wrap-up" produces summary, decisions, action items, unresolved questions
6. Mute/unmute toggleable via wake word, starts muted
7. Q&A pane shows transient clarification pop-ups when MeetBalls can't infer
8. Sessions saved as self-contained folders with descriptive names
9. `--save-here` copies session folder to CWD
10. `meetballs hist` shows interactive scrollable history with summaries
11. Selecting a session in `hist` opens tmux window in that folder
12. `meetballs clean` lists recordings with sizes, confirms, and deletes
13. Speaker diarization uses best available tier (tinydiarize → pyannote → LLM)
14. `meetballs doctor` reports diarization tier status and suggests pyannote
15. All existing tests continue to pass (no regressions)
