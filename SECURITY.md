# Security policy

## Supported versions

Only the latest released version of Nox receives security fixes. Older versions are not patched; please update to the most recent release on the [Releases](../../releases) page.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Instead, open a private security advisory:

1. Go to the [Security tab](../../security) of this repository.
2. Click **Report a vulnerability**.
3. Provide a description, reproduction steps, and the affected version.

This sends the report only to the maintainer and lets us coordinate a fix and disclosure timeline before any public discussion.

## What to expect

- **Acknowledgement:** within 5 business days.
- **Initial assessment:** within 10 business days, including whether the report is in scope and a rough fix timeline.
- **Fix and disclosure:** coordinated with the reporter. Credit given in the release notes unless you prefer to stay anonymous.

## Scope

In scope:

- The Nox macOS application (this repository).
- The release / notarization pipeline in `.github/workflows/release.yml` and `scripts/build-dmg.sh`.

Out of scope (report upstream instead):

- `whisper.cpp` itself — report at https://github.com/ggml-org/whisper.cpp.
- Apple frameworks (AVFoundation, ScreenCaptureKit, FoundationModels, SwiftData) — report via Apple Product Security.
- macOS sandbox / TCC / Gatekeeper behavior — report via Apple Product Security.
- Hugging Face availability or integrity of model files served from `huggingface.co/ggerganov/whisper.cpp`.

For data-flow context and the threat model that informs this scope, see [`THREAT_MODEL.md`](THREAT_MODEL.md).
