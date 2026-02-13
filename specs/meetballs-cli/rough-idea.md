# MeetBalls — Rough Idea

Source: PROMPT.md (design.start event)

Local-first meeting assistant CLI that records audio, transcribes offline via Whisper.cpp,
and enables Q&A via Claude Code CLI. Bash shell scripts, no paid services, Linux/WSL2 only.

Commands: record, transcribe, ask, list, doctor
Storage: ~/.meetballs/{recordings,transcripts,config}
Audio backends: arecord/parecord/pw-record (auto-detect)
Transcription: Whisper.cpp (offline)
Q&A: Claude Code CLI (`claude` command)
Testing: bats-core with mocked externals
