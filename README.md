# Loqui

On-device dictation for iPhone. A custom keyboard with a mic button: tap to start, tap to stop, and the text is typed into whatever app you're in. The audio never leaves the phone.

Inspired by [Handy](https://github.com/cjpais/Handy) on macOS: you pick which speech model to download, with the trade-offs shown per language (accuracy, size, speed).

> **Status:** personal experiment, paused. Dictation, language switching, model download/delete and dictation from the keyboard work on my iPhone 17 Pro (iOS 27). No TestFlight or App Store build yet.

## How it works
- **App** (`Apps/Loqui`): records audio, runs the model, manages downloads. Engines: Parakeet via [FluidAudio](https://github.com/FluidInference/FluidAudio), Whisper via WhisperKit, and Apple SpeechAnalyzer.
- **Keyboard** (`Apps/LoquiKeyboard`): UI only. It talks to the app through an App Group and links no networking or ML code.
- **Shared code** (`Packages/LoquiCore`): IPC protocol, engine adapters, model catalog.

Accuracy numbers in the catalog come from Handy's Italian evaluations (FLEURS). Latency and memory are measured on the device; see `docs/benchmarks/`.

## Privacy check
`scripts/verify-keyboard-privacy.sh` inspects the keyboard binary and fails if it finds URLSession, Network.framework, sockets or any ML engine. Anyone can rerun it.

## Build
Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
```bash
xcodegen generate
open Loqui.xcodeproj
```
Bundle IDs and the App Group are set in `project.yml`; change them there if you fork.

The full plan, decisions and known iOS limits are in [PLAN.md](PLAN.md) (Italian).

Part of [playground-gg](https://github.com/playground-gg).
