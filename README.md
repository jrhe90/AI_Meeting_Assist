# AI Note Taker

A macOS app that records meetings, transcribes them locally, and produces structured summaries. See [`PLAN.md`](PLAN.md) for goals, scope, and build order.

## Requirements

- macOS 26 (Tahoe), Apple Silicon
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [CMake](https://cmake.org/) 3.28+ (`brew install cmake`) — only needed to (re)build the whisper.cpp xcframework

## First-time setup

```sh
git submodule update --init --recursive
( cd Vendor/whisper.cpp && bash build-xcframework.sh )
xcodegen generate
open AINoteTaker.xcodeproj
```

The xcframework build takes a few minutes and only needs to be redone when `Vendor/whisper.cpp` is bumped.

### Whisper model

Until the in-app downloader lands (build step 11), drop the model in place manually. The app is sandboxed, so the model has to live under the sandbox container — not under your home Application Support:

```sh
MODELS=~/Library/Containers/com.ainotetaker.app/Data/Library/Application\ Support/AINoteTaker/models
mkdir -p "$MODELS"
curl -L --progress-bar \
  -o "$MODELS/ggml-small.en.bin" \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin
```

## Subsequent builds

```sh
xcodegen generate
open AINoteTaker.xcodeproj
```

Then build & run the `AINoteTaker` scheme. On first launch, set your development team under **Signing & Capabilities** — the project uses automatic signing.

Headless build to verify changes:

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
PLAN.md             # Design doc and build order
```

## License

MIT — see [`LICENSE`](LICENSE).
