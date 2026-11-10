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

**There is nothing to download and install directly.** No App Store, no TestFlight, no `.ipa`. The only way to get Loqui on your iPhone is to build it from source with Xcode, signed with your own Apple ID. That's a consequence of the project having no paid Apple Developer account: see [Why there's no download link](#why-theres-no-download-link).

**You need:**

- a Mac with Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Without a Mac you can't install Loqui;
- an iPhone on iOS 26 or later, and a cable;
- an Apple ID. A free one works, with the [weekly renewal](#free-apple-id-the-weekly-renewal) described below.

**Steps:**

1. Sign in with your Apple ID in *Xcode → Settings → Accounts*. If you've never signed an app on this Mac, select your team there, click *Manage Certificates…* and add an *Apple Development* certificate.
2. On the iPhone, turn on *Settings → Privacy & Security → Developer Mode* (it appears after the phone has been connected to Xcode once) and restart when asked.
3. Connect the iPhone with a cable, unlock it, and run:
   ```bash
   git clone https://github.com/playground-gg/loqui.git
   cd loqui
   scripts/install.sh
   ```
   The script asks for an identifier prefix (for example `com.yourname`), finds your team and your iPhone, builds the app, runs the keyboard privacy check and installs it. The first build takes several minutes.
4. The first time, the app won't open until you trust your developer certificate on the iPhone: *Settings → General → VPN & Device Management*.

Your choices are saved in `.env.local` and `Config/Local.xcconfig`, both ignored by git, so the next run asks nothing.

**About the prefix.** App and keyboard identifiers are built from one prefix, set in [`Config/Identifiers.xcconfig`](Config/Identifiers.xcconfig). The default belongs to the author's Apple team and Xcode won't sign it for anyone else, which is why you pick your own. Choose it once and keep it: a free Apple ID can register only 10 new identifiers every 7 days, and Loqui uses two.

**Prefer Xcode?** Create `Config/Local.xcconfig` containing `LOQUI_ID_PREFIX = com.yourname`, run `xcodegen generate`, open `Loqui.xcodeproj`, select your team under *Signing & Capabilities* for both the **Loqui** and **LoquiKeyboard** targets, and press Run.

### Free Apple ID: the weekly renewal

Apps signed with a free Apple ID stop working **7 days** after Xcode signed them. This is Apple's rule for free accounts, not something Loqui can change.

**What happens when it expires**

- Loqui no longer opens (iOS says the app is no longer available) and the keyboard stops working.
- Nothing is deleted. Downloaded models and settings stay on the phone as long as you don't delete the app.

**How to renew (about a minute)**

1. Connect the iPhone to the Mac and unlock it.
2. Run `scripts/install.sh` again (or press Run in Xcode).

That's all: the app is signed again and installed over the old one, and you get another 7 days. Don't delete the app first, or you'll have to download the models again. You shouldn't need to add the keyboard or trust the certificate again, though that hasn't been checked across many renewals.

**Good to know**

- The 7 days count from when Xcode created the signing profile, not from the last time you opened the app. There's no warning before it expires: a weekly reminder helps.
- You need the Mac every week. There's no way to renew from the iPhone alone.
- A free Apple ID can keep at most 3 self-built apps on a device at the same time.
- With a paid Apple Developer membership (99 USD a year) the same build lasts **one year** instead of 7 days. Nothing else changes in the steps above.
- Tools like AltStore or SideStore, which re-sign apps automatically, need an `.ipa` file. This repo doesn't publish one and that route is untested.

### Why there's no download link

Sharing an iOS app outside your own devices needs a paid Apple Developer account, and this project doesn't have one:

- **App Store and TestFlight** are only available to paid accounts.
- **A prebuilt `.ipa` wouldn't help.** An app signed with a free Apple ID runs only on the devices of the person who signed it.
- Even with a paid account, the App Store isn't a given: Apple's rules for keyboards make parts of Loqui's flow uncertain to get approved (see Limits). TestFlight would be the realistic first step, and its builds expire after 90 days.

So for now: the code is public, and everyone signs their own copy.

## Use

1. Open Loqui, allow the microphone, choose your languages and download a model.
2. Add the keyboard: *Settings → General → Keyboard → Keyboards → Add New Keyboard → Loqui*, then turn on **Allow Full Access** (needed for the keyboard to talk to the app; see Privacy).
3. In any text field, hold or tap 🌐 and pick Loqui. Speak, tap to stop.

The microphone has to stay on in the Loqui app for the keyboard to start dictation without opening it (iOS doesn't let keyboards record audio). After you open Loqui, it stays ready for a time you choose (3 minutes by default) and iOS shows the orange microphone dot meanwhile. When that runs out, open Loqui again.

## Limits

- **Build it yourself, on a Mac.** No App Store, no TestFlight, no download: see [Install](#install).
- **Free Apple ID:** the app expires every 7 days and has to be reinstalled from Xcode. See [the weekly renewal](#free-apple-id-the-weekly-renewal).
- **App Store approval is uncertain.** Apple's rules for keyboards don't clearly allow parts of this flow.
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
