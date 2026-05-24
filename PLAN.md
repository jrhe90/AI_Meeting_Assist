# AI Note Taker — Project Plan

A macOS app that records meetings, transcribes them in real time, and produces structured summaries. Local-by-default, inspired by Meetily.

---

## 1. Goals & positioning

- **Type:** Open-source side project (MIT license).
- **Pitch:** "Private, on-device meeting notes for Mac. Your audio never leaves your machine."
- **Audience:** Privacy-conscious Mac users; devs; people in regulated work (legal, medical, exec).
- **Non-goals (v1):** Cross-platform, team collaboration, cloud sync, calendar/Zoom auto-detect.

## 2. Platform & stack

| Concern | Choice |
|---|---|
| Min macOS | **26 Tahoe** (for `FoundationModels` framework) |
| Architecture | Apple Silicon only (no Intel) |
| Language | Swift |
| UI | SwiftUI + AppKit interop where needed |
| App shape | Menubar app (primary) + on-demand window (meeting library / editor) |
| Persistence | SwiftData (in-app) + auto-export to Markdown files |
| Audio capture (system) | ScreenCaptureKit (`SCStream` with `audio: true`, `excludesCurrentProcessAudio: true`) |
| Audio capture (mic) | AVAudioEngine |
| Transcription | whisper.cpp (Core ML + Metal), `small.en` default |
| Summarization | Apple Foundation Models (`@Generable` guided generation) |
| Distribution | GitHub Releases (.dmg, notarized) |
| License | MIT |

## 3. Privacy posture

- Default flow is 100% local: audio → whisper.cpp → Foundation Models → SwiftData. No network calls.
- Raw audio is discarded after transcription completes.
- No telemetry, no crash reporting, no analytics — ever.
- Claude API backup is **opt-in** and deferred to v1.1+. When enabled, transcript text (not audio) is sent to Anthropic with explicit user consent per meeting.

## 4. UX flow

### First launch (onboarding wizard)
1. Welcome screen: what the app does, privacy stance.
2. Permission requests, one at a time with rationale:
   - Microphone
   - Screen Recording (required for system audio via ScreenCaptureKit)
3. Whisper model download with progress (`small.en`, ~466MB from Hugging Face).
4. Done — drop into menubar.

### During a meeting
1. User clicks menubar icon → **Start meeting**.
2. Menubar icon flips to "Recording" state.
3. Popover (or detached window) shows live transcript as it streams in, with **Me** / **Others** speaker labels.
4. User clicks **Stop**.
5. Summary is generated in-place; user sees TL;DR + Decisions + Action Items + Topics.

### Post-meeting
- Meeting appears in the library window.
- Transcript is editable per-segment (fix names, jargon).
- Summary is editable as Markdown.
- Each meeting auto-exports to `~/Documents/AI Note Taker/<date>-<title>.md`.

## 5. Diarization strategy

Cheap split: capture mic and system audio as two separate streams, transcribe each with its own whisper.cpp instance, merge segments by start timestamp. Mic-side segments label as **Me**, system-side as **Others**. Good enough for ~all 1:1 and most group calls; doesn't distinguish individuals among "Others".

Full multi-speaker diarization (pyannote / sherpa-onnx) is deferred to v2.

## 6. Summary schema

Foundation Models with guided generation. Swift type:

```swift
@Generable
struct MeetingSummary {
    let tldr: String              // 1-3 sentences
    let decisions: [String]       // each is one decision
    let actionItems: [ActionItem]
    let topics: [Topic]
}

@Generable
struct ActionItem {
    let description: String
    let assignee: String?         // best-effort from transcript
    let dueDate: String?          // best-effort
}

@Generable
struct Topic {
    let title: String
    let bullets: [String]
}
```

For meetings that exceed the on-device context window, transcript is chunked and summarized hierarchically (see Risks §10.2).

## 7. Module layout

Single Xcode project (`AINoteTaker.xcodeproj`) with local Swift Packages:

```
AI_Note_Taker/
├── AINoteTaker.xcodeproj
├── App/                       # SwiftUI app target, menubar, windows, onboarding
│   ├── AINoteTakerApp.swift
│   ├── Menubar/
│   ├── Onboarding/
│   ├── Library/
│   └── MeetingDetail/
├── Packages/
│   ├── AudioCapture/          # ScreenCaptureKit + AVAudioEngine, dual-stream
│   ├── Transcription/         # whisper.cpp bridge, streaming chunker
│   ├── Summarization/         # FoundationModels client, hierarchical summarizer
│   ├── Storage/               # SwiftData models + Markdown exporter
│   └── SharedKit/             # Logger, types, utilities
├── Resources/
│   └── (no bundled model — downloaded at first run)
└── PLAN.md
```

Each package has its own unit tests under `Tests/`.

## 8. v1.0 scope

**In:**
- Menubar app with start/stop recording.
- Permissions onboarding wizard.
- First-run whisper model download.
- Dual-stream audio capture (mic + system via ScreenCaptureKit).
- Live streaming transcription with Me/Others labels.
- Foundation Models structured summary.
- Library window listing past meetings.
- Editable transcript (per segment) and summary (Markdown editor).
- SwiftData persistence + auto Markdown export to `~/Documents/AI Note Taker/`.
- Notarized .dmg on GitHub Releases.

**Out (deferred to v1.1+):**
- Claude API backup for summarization.
- Sparkle auto-update.
- Swappable whisper models from settings UI.
- Full-text search across meeting history.

**Out (v2+):**
- Calendar / Zoom / Meet / Teams auto-detect.
- Multi-speaker diarization (named individuals).
- Floating overlay during meetings.
- Cross-platform.

## 9. Build order

Each step ends in something demoable.

1. **Xcode skeleton** — empty SwiftUI app, menubar item, basic library window. Verify it launches.
2. **Permissions onboarding** — wizard UI, request mic + screen recording, persist "completed" flag.
3. **Audio capture spike** — ScreenCaptureKit grabs system audio to disk; AVAudioEngine grabs mic to disk; play back both files to verify quality and that they capture independently. *This is the highest-risk step — do not move on until both files sound right.*
4. **Whisper integration** — vendor whisper.cpp, build with Core ML + Metal, expose a Swift wrapper. Transcribe a saved WAV end-to-end. Confirm `small.en` runs faster than real-time on the target machine.
5. **Streaming pipeline** — split incoming audio into ~10s chunks with ~2s overlap, feed to whisper, emit segments with timestamps to a SwiftUI view. Dual-stream version emits Me/Others labels.
6. **SwiftData model** — `Meeting`, `TranscriptSegment`, `Summary`, `ActionItem`, etc. Persist a live meeting as segments stream in.
7. **Foundation Models summarizer** — feed completed transcript, get `MeetingSummary` back. Render in the meeting-detail view.
8. **Hierarchical summarization** — chunk transcripts that exceed context, summarize chunks, then summarize summaries.
9. **Editing UX** — inline transcript editing (per segment), Markdown editor for summary, write-through to SwiftData and re-export to .md.
10. **Library polish** — list, sort by date, delete, open meeting detail.
11. **Onboarding polish + model download** — wire the wizard to a real Hugging Face download with progress + resume.
12. **Notarization + .dmg** — Apple Developer account ($99/yr), set up signing, create-dmg, GitHub Actions release workflow.

Rough effort: 4–6 weekends for someone comfortable in Swift, longer if learning ScreenCaptureKit and whisper.cpp bridging from scratch.

## 10. Risks & mitigations

### 10.1 ScreenCaptureKit audio quirks
Capturing system audio without video is supported but has surprising behavior across macOS versions (sample rate drift, occasional silence on output device changes). **Mitigation:** spike step 3 first; build a smoke-test that records 60s and verifies sample count is within expected range. Log all `SCStream` errors loudly.

### 10.2 Foundation Models context window
On-device model context is limited (~4k tokens depending on Tahoe build). A 60-min meeting transcript at ~150 wpm = ~9000 words ≈ ~12k tokens, well over budget. **Mitigation:** hierarchical summarization — chunk transcript by topic shift or fixed window (e.g. 10 min), summarize each chunk, then summarize the chunk-summaries. Prototype this on a real long transcript before committing UI to the structured schema.

### 10.3 macOS 26 minimum cuts user base
As of May 2026, Tahoe adoption is partial; users on Sonoma/Sequoia can't run the app at all. **Mitigation accepted:** side project, fine to be cutting-edge. If demand emerges for older OS support, add an embedded llama.cpp + GGUF model as a fallback summarizer (real work, not v1).

### 10.4 Whisper hallucinations on silence
Whisper invents text during silent chunks (e.g. "Thank you." "Bye."). **Mitigation:** RMS energy gate — skip chunks below a silence threshold. Optional VAD (Silero) as v1.1 polish.

### 10.5 Mic/system audio time sync
Two independent capture pipelines have different latencies; naively merging by wall clock breaks ordering. **Mitigation:** use sample-accurate timestamps from `AVAudioPCMBuffer.audioTimeStamp` / `CMSampleBuffer.presentationTimeStamp`, and a single monotonic clock for merging.

### 10.6 Notarization friction
First notarization run usually fails on entitlements. **Mitigation:** notarize early (after step 4 or 5), not at the end. Catches signing/entitlement issues before they pile up.

## 11. Entitlements & Info.plist (reference)

- `NSMicrophoneUsageDescription` — "AI Note Taker uses your microphone to capture your side of meetings."
- `NSScreenCaptureUsageDescription` (informal — actual key is via TCC) — "AI Note Taker captures system audio so it can transcribe what other participants say."
- App is sandboxed; entitlements:
  - `com.apple.security.device.audio-input`
  - `com.apple.security.network.client` (only if Claude opt-in is built; off by default)
  - No `com.apple.security.files.user-selected.read-write` needed beyond the Markdown export path.

## 12. Open questions to revisit before coding

- App name (placeholder: "AI Note Taker") — pick something searchable before v1 release.
- Icon / branding.
- Foundation Models exact token budget on shipping Tahoe build — verify with a one-off probe.
- Whether to bundle the `small.en` Core ML encoder (~few hundred MB) or download it alongside the model.
