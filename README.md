# Loqui

**On-device dictation for iPhone.** Switch to the Loqui keyboard, speak, tap, and the text lands in whatever app you're typing in. The speech model runs on the phone's Neural Engine: no account, no subscription, and the audio never leaves the device.

## Why

On my Mac I use [Handy](https://github.com/cjpais/Handy): free, open source, offline, and you choose which speech model to run. I wanted the same thing on my iPhone and couldn't find it, so I built it. It's a personal experiment, not a product.

## What it does

- **Dictation from any app** through a custom keyboard. Pick Loqui from the 🌐 key, dictation starts by itself, tap to stop, the text is inserted and you're back on your usual keyboard.
- **Tap to talk.** First tap starts, second tap stops. Pauses don't cut you off. The whole recording is transcribed after you stop, usually in well under a second.
- **Choose your model**, like Handy. Each one shows its size and how well it does per language, so you can trade accuracy for space.
- **Multilingual.** Pick "my languages" (31 available) and switch from the keyboard. Parakeet handles Italian and English in the same sentence without being told.
- **Undo** throws away the dictation in progress.

## Models

| Model | Download | Notes |
|---|---:|---|
| Parakeet Ultra | ~600 MB | Recommended. Most accurate on Italian, fastest on device, handles mixed languages |
| Parakeet TDT v3 | ~600 MB | Slightly less accurate than Ultra |
| Whisper large-v3-turbo | ~630 MB | Good accuracy, but can silently drop a sentence when you switch language |
| Whisper small | ~250 MB | Smallest download, less accurate |
| Apple SpeechAnalyzer | managed by iOS | Nothing to download from Loqui; max 5 languages |

Accuracy figures come from [Handy's evaluations](https://models.handy.computer/languages/it) (FLEURS, Italian). Speed and memory were measured on an iPhone 17 Pro: a 7-second clip takes about 0.07 s with Parakeet and about 1 s with Whisper turbo. Full numbers in [`docs/benchmarks/`](docs/benchmarks/).

## Install

There's no App Store or TestFlight build. You build it yourself with Xcode.

**You need:** a Mac with Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), an iPhone on iOS 26 or later, and an Apple ID (a free one works).

1. Clone and generate the project:
   ```bash
   git clone https://github.com/playground-gg/loqui.git
   cd loqui
   xcodegen generate
   open Loqui.xcodeproj
   ```
2. In Xcode, select your team under *Signing & Capabilities* for both the **Loqui** and **LoquiKeyboard** targets. If you fork it, change the bundle IDs and App Group once in `project.yml`.
3. Plug in the iPhone, pick it as the destination and press Run.
4. On the iPhone, trust your developer certificate: *Settings → General → VPN & Device Management*.

## Use

1. Open Loqui, allow the microphone, choose your languages and download a model.
2. Add the keyboard: *Settings → General → Keyboard → Keyboards → Add New Keyboard → Loqui*, then turn on **Allow Full Access** (needed for the keyboard to talk to the app; see Privacy).
3. In any text field, hold or tap 🌐 and pick Loqui. Speak, tap to stop.

The microphone has to stay on in the Loqui app for the keyboard to start dictation without opening it (iOS doesn't let keyboards record audio). After you open Loqui, it stays ready for a time you choose (3 minutes by default) and iOS shows the orange microphone dot meanwhile. When that runs out, open Loqui again.

## Limits

- **Free Apple ID:** the app expires after 7 days and has to be reinstalled from Xcode.
- **Not on the App Store.** Apple's rules for keyboards make parts of this flow uncertain to get approved.
- **Orange mic indicator** while Loqui is ready, by design. Battery cost of staying ready isn't measured yet.
- **No automatic return to the app you were in** if dictation has to open Loqui first. iOS has no public API for it, so you switch back yourself.
- **No live text.** You see the text after you stop, not while you speak.
- **Cold start.** The first dictation after the app was closed loads Parakeet in about 10 s. After that it's instant.
- **Tested on one phone** (iPhone 17 Pro, iOS 27). With more than two keyboards enabled, Loqui may hand back to the next one instead of the one you came from.
- Not built yet: Action Button, Control Center, Live Activity, personal dictionary, history.

## Privacy

- The keyboard contains no networking code. [`scripts/verify-keyboard-privacy.sh`](scripts/verify-keyboard-privacy.sh) checks the built binary and fails if it finds URLSession, Network.framework, sockets or an ML engine. Run it yourself.
- The app uses the network only to download models. No analytics, no telemetry, no account.
- Audio stays in memory and isn't written to disk.
- iOS shows its standard warning when you enable Full Access. That's why the check above exists.

## How it's built

- `Apps/Loqui`: the app. Microphone, models, downloads, settings.
- `Apps/LoquiKeyboard`: the keyboard. UI only, talks to the app through an App Group.
- `Packages/LoquiCore`: shared protocol, engine adapters ([FluidAudio](https://github.com/FluidInference/FluidAudio) for Parakeet, [WhisperKit](https://github.com/argmaxinc/WhisperKit) for Whisper, Apple SpeechAnalyzer) and the model catalog.

Plan, decisions and known iOS constraints are in [`PLAN.md`](PLAN.md) (in Italian).

## License

[Unlicense](LICENSE): public domain, do whatever you want with it. Dependencies and models keep their own licenses (FluidAudio Apache 2.0, WhisperKit MIT, Parakeet CC-BY-4.0).

Part of [playground-gg](https://github.com/playground-gg), small experiments built in the open.
