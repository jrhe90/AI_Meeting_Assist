# AI Note Taker

A macOS app that records meetings, transcribes them locally, and produces structured summaries. See [`PLAN.md`](PLAN.md) for goals, scope, and build order.

## Requirements

- macOS 26 (Tahoe), Apple Silicon
- Xcode 26 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

The Xcode project is generated from [`project.yml`](project.yml) and is **not** checked in.

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
