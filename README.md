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

The first-run onboarding wizard downloads `ggml-small.en.bin` (~466 MB) into the sandbox container and resumes if interrupted. Nothing to do manually.

If you'd rather drop it in by hand (e.g. air-gapped install), put it here:

```
~/Library/Containers/com.ainotetaker.app/Data/Library/Application Support/AINoteTaker/models/ggml-small.en.bin
```

The wizard detects an existing file by size and skips the download.

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
scripts/            # Release helpers (build-dmg.sh)
.github/workflows/  # CI release workflow
PLAN.md             # Design doc and build order
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
NOTARY_PROFILE=ainotetaker-release \  # set up once via `xcrun notarytool store-credentials`
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

## License

MIT — see [`LICENSE`](LICENSE).
