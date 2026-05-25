# Nox

> Local-first meeting recorder for macOS. Your audio never leaves your machine.

Nox records meetings, transcribes them on-device with [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp), and produces structured summaries (TLDR, decisions, action items, topics) using Apple's on-device LLM (`FoundationModels`). It captures both sides of the call — your microphone and system audio — without ever uploading anything.

The internal target / repository name is `AINoteTaker` (kept for permission and data continuity); the user-facing brand is **Nox**.

---

## Install

Download the latest signed, notarized DMG from [Releases](../../releases). On first launch, an onboarding wizard requests microphone + screen-recording permissions and downloads the whisper model (~466 MB for the default `ggml-small.en`).

**Requirements:** macOS 26 (Tahoe), Apple Silicon.

## What Nox does

- **Captures both sides** — mic (`AVAudioEngine`) and system audio (`ScreenCaptureKit`, audio-only).
- **Transcribes locally** with `whisper.cpp`. Sticky per-meeting language detection avoids the per-chunk auto-detect failure mode on short non-English clips.
- **Summarizes locally** with Apple's on-device LLM. Hierarchical summarization for long meetings keeps quality stable past the model's context window.
- **Produces structured notes** — TLDR, decisions, action items (with assignee + due date when stated), topics with bullets.
- **Exports to Markdown** for paste into Obsidian / Notion / wherever.
- **Ships as a menubar app** — no dock icon, no window unless you open one.

## Why Nox vs Granola / Limitless

|  | Nox | Granola | Limitless |
|---|---|---|---|
| Audio stays on device | Yes | No (transcription + summarization cloud-side) | No |
| Summarization model | Apple FoundationModels (on-device) | Cloud LLM | Cloud LLM |
| Works offline after install | Yes | No | No |
| Open source | Yes (MIT) | No | No |
| Price | Free | Free tier + paid | Paid subscription |
| Inspectable / forkable | Yes | No | No |

Pick Nox if you want your meeting audio to never leave the Mac, want to read or change the code, and don't want a subscription. Pick the others if you want cloud features (multi-device sync, hosted history, shared workspaces) and aren't worried about audio egress.

## Privacy

- Audio buffers exist in memory only. They are never written to disk.
- Transcripts and summaries are stored in the app sandbox container at `~/Library/Containers/com.ainotetaker.app/`.
- The only outbound network call is the one-time whisper model download from Hugging Face during onboarding. No analytics, no crash reporting, no update checks, no remote config.
- See [`THREAT_MODEL.md`](THREAT_MODEL.md) for the full data-flow analysis, permissions table, and dependency list.

---

## Build from source

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), CMake 3.28+ (`brew install cmake`) — CMake is only needed to (re)build the `whisper.cpp` xcframework.

```sh
git submodule update --init --recursive
( cd Vendor/whisper.cpp && bash build-xcframework.sh )
xcodegen generate
open AINoteTaker.xcodeproj
```

The xcframework build takes a few minutes and only needs to be redone when `Vendor/whisper.cpp` is bumped.

### Whisper model

The onboarding wizard downloads `ggml-small.en.bin` (~466 MB) into the sandbox container on first run and resumes if interrupted. To drop it in by hand (e.g. air-gapped install):

```
~/Library/Containers/com.ainotetaker.app/Data/Library/Application Support/AINoteTaker/models/ggml-small.en.bin
```

The wizard detects an existing file by size and skips the download.

### Subsequent builds

```sh
xcodegen generate
open AINoteTaker.xcodeproj
```

Build & run the `AINoteTaker` scheme. On first launch, set your development team under **Signing & Capabilities** — the project uses automatic signing.

Headless build:

```sh
xcodebuild -project AINoteTaker.xcodeproj \
           -scheme AINoteTaker \
           -configuration Debug \
           -destination 'platform=macOS,arch=arm64' \
           build
```

## Layout

```
App/                # SwiftUI app target (menubar, windows, onboarding)
Packages/           # Local Swift packages (AudioCapture, Transcription,
                    # Summarization, Storage, SharedKit)
project.yml         # XcodeGen spec — edit this, not the .xcodeproj
scripts/            # Release helpers (build-dmg.sh)
.github/workflows/  # CI release + supply-chain workflows
PLAN.md             # Design doc and build order
THREAT_MODEL.md     # Data flows, permissions, dependencies
```

## Publishing a release

Releases are signed, notarized, and shipped as a `.dmg` to GitHub Releases. This requires:

- An **Apple Developer Program** account ($99/year). Free Apple IDs cannot notarize.
- A **Developer ID Application** certificate, generated at developer.apple.com → Certificates.
- An **App Store Connect API key** (or app-specific password) for `notarytool`.

### Local build

```sh
brew install create-dmg

DEV_TEAM_ID=ABCDE12345 \
APP_BUNDLE_ID=com.ainotetaker.app \
APP_VERSION=1.0.0 \
NOTARY_PROFILE=ainotetaker-release \
./scripts/build-dmg.sh
```

The script archives a Release build, notarizes the `.app`, wraps it in a `.dmg` with `create-dmg`, then notarizes and staples the `.dmg` itself. Output lands in `build/dist/AINoteTaker-<version>.dmg`.

### CI build (GitHub Actions)

Push an annotated `v1.2.3` tag and `.github/workflows/release.yml` runs the same script on a `macos-26` runner, uploading the signed DMG to a draft GitHub Release.

Required repository secrets:

| Secret | What |
|---|---|
| `DEV_TEAM_ID` | 10-character Apple Developer team ID |
| `SIGNING_CERT_P12_BASE64` | Developer ID Application cert exported from Keychain as `.p12`, then base64-encoded |
| `SIGNING_CERT_PASSWORD` | Password chosen when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | Anything — secures the ephemeral keychain on the runner |
| `NOTARY_KEY_ID` | App Store Connect API key ID |
| `NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `NOTARY_KEY_P8_BASE64` | The `AuthKey_<id>.p8` file base64-encoded |

## Contributing

Issues and PRs welcome. The design doc and build order live in [`PLAN.md`](PLAN.md); the security and data-flow analysis lives in [`THREAT_MODEL.md`](THREAT_MODEL.md).

## License

MIT — see [`LICENSE`](LICENSE).
