# Nox — Threat Model

This document describes what data Nox handles, where it lives, what crosses the network, and which threats the design considers (and which it does not). It is intended as a starting point for self-review and for enterprise security teams evaluating Nox for installation on managed devices.

Repository: https://github.com/jrhe90/AI_Meeting_Assist
License: MIT

## 1. System overview

Nox is a sandboxed macOS app (macOS 26 Tahoe, Apple Silicon) that:

1. Captures microphone audio (your voice) and system-output audio (other meeting participants).
2. Transcribes both streams locally using `whisper.cpp`.
3. Summarizes the combined transcript locally using Apple's `FoundationModels` framework (on-device LLM).
4. Persists meetings, transcripts, and summaries to a local SwiftData store inside the app sandbox.
5. Optionally exports a markdown file to the sandbox `Documents` folder.

Nox does **not** stream audio, transcripts, or summaries to any server. The only outbound network call is the one-time whisper model download from Hugging Face during onboarding.

## 2. Data Nox handles

| Data | Source | Where it lives | Lifetime |
|---|---|---|---|
| Raw audio (PCM buffers) | AVAudioEngine (mic) + ScreenCaptureKit (system audio) | In-memory only — never written to disk | Discarded once consumed by whisper |
| Transcript segments | whisper.cpp output | SwiftData store inside app sandbox | Until the user deletes the meeting |
| Meeting summaries | FoundationModels output | SwiftData store inside app sandbox | Until the user deletes the meeting |
| Markdown exports | Generated from a stored meeting | `~/Library/Containers/com.ainotetaker.app/Data/Documents/Nox/` | Until the user deletes the file |
| User preferences | UserDefaults | `~/Library/Containers/com.ainotetaker.app/Data/Library/Preferences/` | Until app uninstall |
| Whisper model file (`ggml-*.bin`) | Hugging Face download | `~/Library/Containers/com.ainotetaker.app/Data/Library/Application Support/AINoteTaker/models/` | Until app uninstall or user removes |

All persistent data is confined to the app sandbox container at `~/Library/Containers/com.ainotetaker.app/`.

## 3. Trust boundaries

```
+-------------------+        +----------------------------+
|  macOS (TCC)      |  --->  |  Nox sandbox container     |
|  - mic permission |        |  - SwiftData store         |
|  - screen-capture |        |  - markdown exports        |
|    permission     |        |  - whisper model           |
+-------------------+        |  - preferences             |
                             +----------------------------+
                                          |
                                          |  outbound HTTPS, onboarding only
                                          v
                             +----------------------------+
                             | huggingface.co             |
                             | (whisper model download)   |
                             +----------------------------+
```

Trust boundaries crossed:
- **User → Nox**: user explicitly grants mic + screen-recording TCC permissions on first run. Without both, capture fails closed.
- **Nox → Hugging Face**: outbound HTTPS GET for the chosen whisper model. No request body, no auth headers, no telemetry. URL is hard-coded per model in `Packages/Transcription/Sources/Transcription/WhisperModel.swift`.
- **Nox → Apple FoundationModels**: in-process call to an on-device framework. No network involvement.

## 4. Network calls (exhaustive list)

| When | URL | Direction | Payload | Auth |
|---|---|---|---|---|
| First-run onboarding (and model swap) | `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-<model>.bin` | Outbound HTTPS GET | None (URL only) | None |

That is the complete network surface. There are no analytics, no crash reporting, no telemetry, no update checks, no remote config. Verifiable: `grep -rE "URLSession\|URLRequest\|https?://" App/ Packages/ --include="*.swift"` returns only the Hugging Face URLs and the SwiftUI machinery to fetch them.

The `com.apple.security.network.client` entitlement is retained after onboarding to support a future optional Claude API integration (see `PLAN.md` §3). It is not currently exercised by any code path other than the model downloader.

## 5. macOS permissions and entitlements

From `App/AINoteTaker.entitlements`:

| Entitlement | Why |
|---|---|
| `com.apple.security.app-sandbox` | App runs sandboxed. |
| `com.apple.security.device.audio-input` | Microphone capture via AVAudioEngine. |
| `com.apple.security.network.client` | Whisper model download from Hugging Face. |
| `com.apple.security.cs.disable-library-validation` | Required to load the locally-built `whisper.cpp` xcframework, which is signed with a placeholder team ID. Production notarized builds re-sign the framework with the Developer ID Application certificate; this entitlement can be removed once the build script is updated to re-sign in-place. |

From `App/Info.plist`:

| Usage description | Purpose |
|---|---|
| `NSMicrophoneUsageDescription` | "Nox uses your microphone to capture your side of meetings. Audio is processed entirely on your device." |
| `NSScreenCaptureUsageDescription` | "Nox captures system audio so it can transcribe what other participants say. No video is recorded and audio never leaves your device." |

Nox does **not** request: contacts, calendar, reminders, photos, location, full-disk access, automation, or accessibility.

Notes on `NSScreenCaptureUsageDescription`: ScreenCaptureKit is invoked in audio-only mode (`SCStream` with audio capture enabled, no video buffers retrieved). The `Privacy & Security → Screen Recording` permission name is misleading — Nox never captures pixels.

## 6. Third-party dependencies

| Dependency | Version pin | License | Purpose | Source |
|---|---|---|---|---|
| `whisper.cpp` (ggml-org) | Git submodule at `Vendor/whisper.cpp` | MIT | Local speech-to-text | https://github.com/ggml-org/whisper.cpp |
| Whisper model weights (`ggml-*.bin`) | Pinned per-model | MIT (model weights) | Whisper inference | https://huggingface.co/ggerganov/whisper.cpp |

First-party-only (no third-party dependency): all Swift packages under `Packages/` (AudioCapture, Transcription, Summarization, Storage, SharedKit). Apple frameworks (AVFoundation, ScreenCaptureKit, SwiftData, SwiftUI, FoundationModels) are first-party.

No Swift Package Manager dependencies are declared in any `Package.swift`.

## 7. Build and distribution

- Source builds via Xcode + XcodeGen from `project.yml`.
- Release builds via `scripts/build-dmg.sh` and GitHub Actions (`.github/workflows/release.yml`) on `macos-26` runners.
- Releases are signed with a Developer ID Application certificate and notarized via `notarytool`. The signed and stapled `.dmg` is published to GitHub Releases.
- The whisper.cpp xcframework is rebuilt from the pinned submodule (`Vendor/whisper.cpp/build-xcframework.sh`); no prebuilt binary is downloaded at build time.
- Secrets used by CI (Apple certificates, notary key) are stored as GitHub Actions repository secrets — not in the source tree.

## 8. Threats considered

| Threat | Mitigation | Residual |
|---|---|---|
| Audio leaving the device | No outbound network call carries audio/transcript/summary. Network entitlement is used only for model download. | Misconfiguration if a future code change introduces a new outbound call — caught by code review + the explicit list in §4. |
| Compromised whisper model from upstream | Model URL points at `huggingface.co/ggerganov/whisper.cpp`, the canonical upstream maintained by whisper.cpp's author. HTTPS only. | Hugging Face account compromise. Mitigation: pin model checksums (not currently done — see §10). |
| Compromised whisper.cpp source | Submodule pinned to a specific commit in `Vendor/whisper.cpp`. Updates are explicit `git submodule update` operations. | A malicious upstream commit landing before pin is bumped. Mitigation: review submodule bumps; consider OSSF Scorecard for upstream. |
| Tampered release artifact | Releases are notarized by Apple; users get a Gatekeeper warning if the signature or notarization is invalid. CI workflow logs are public. | Compromise of the Apple Developer signing identity or App Store Connect API key — out of scope; handled by Apple ID security. |
| Local data theft (another user/process on the Mac) | App-sandbox container; SwiftData store inside the container. Other user accounts cannot read it without elevation. | A root process on the Mac can read anything; out of scope. |
| Permission abuse (mic or screen capture used outside meetings) | Capture is only initiated from explicit user actions (start meeting button). No background capture. | Bug in capture state machine that fails to stop capture. Mitigation: code review of `AudioCapture` package; visible menubar indicator when recording. |
| Supply-chain attack via build dependencies | No Swift Package Manager dependencies. Only third-party dep is the pinned whisper.cpp submodule. | Compromise of Apple's toolchain or runner images — out of scope. |
| Untrusted input from transcription | Whisper output is rendered into the UI and into markdown exports. SwiftUI's `Text` and markdown rendering do not execute scripts. Markdown exports are static `.md` files. | Markdown viewers that render embedded HTML/JS — out of Nox's scope. |
| Update mechanism abuse | Nox has no in-app updater. Users update by downloading a new notarized DMG from GitHub Releases. | None inherent. |

## 9. Out of scope

- Threats requiring root or physical access to the device.
- Compromise of macOS itself, the Hugging Face CDN, GitHub, or Apple's notary service.
- Network-level adversaries with the ability to intercept TLS between the device and Hugging Face (TLS is trusted as configured by macOS).
- Data classification regimes beyond standard personal/business audio (e.g., HIPAA, FedRAMP) — Nox makes no claims of certification.
- Adversaries with the ability to install other software on the same user account (e.g., a malicious app reading the sandbox container via TCC bypass).

## 10. Known gaps

- **Whisper model checksum pinning.** Models are downloaded by URL without a published SHA-256 to compare against. Bumping the downloader to verify a checksum would close the "compromised model" gap.
- **Library validation disabled.** `com.apple.security.cs.disable-library-validation` is set to load the locally-built whisper xcframework. Removing this requires the release build to re-sign the xcframework with the Developer ID Application certificate before bundling. Tracked alongside step 12 of `PLAN.md`.
- **No SBOM published yet.** A CycloneDX SBOM is on the roadmap; the current dependency list (§6) serves as the manual equivalent.

## 11. Reporting a vulnerability

If you believe you have found a security issue in Nox, please open a private security advisory on the GitHub repository rather than filing a public issue. (See `SECURITY.md`.)
