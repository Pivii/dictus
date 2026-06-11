<p align="center">
  <img src="assets/brand/appicon-light.svg" alt="Dictus" width="120" height="120" />
</p>

<h1 align="center">Dictus for iOS</h1>

<p align="center">
  <strong>Free, open-source iOS keyboard for voice dictation — 100% on-device.</strong><br />
  Speak in any app. No cloud, no account, no subscription.
</p>

<p align="center">
  <a href="https://github.com/getdictus/dictus-ios/actions/workflows/ci.yml"><img src="https://github.com/getdictus/dictus-ios/actions/workflows/ci.yml/badge.svg?branch=develop" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey.svg" alt="Platform: iOS 17+" />
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange.svg" alt="Swift 5.9+" />
  <a href="https://github.com/getdictus/dictus-ios/stargazers"><img src="https://img.shields.io/github/stars/getdictus/dictus-ios?style=social" alt="Stars" /></a>
</p>

<p align="center">
  <a href="https://getdictus.com">Website</a> ·
  <a href="https://testflight.apple.com/join/b55atKYX">TestFlight beta</a> ·
  <a href="https://github.com/getdictus/dictus-android">Android</a> ·
  <a href="https://github.com/getdictus/dictus-desktop">Desktop</a> ·
  <a href="https://t.me/getdictus">Community</a>
</p>

---

Dictus is a free, open-source iOS keyboard that adds voice dictation to any app. All speech recognition runs on-device via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple CoreML) — no server, no account, no subscription. French-first, with English and German support.

## Why Dictus?

- 🔒 **100% on-device** — your voice never leaves the iPhone. No cloud, no telemetry, no account.
- 🆓 **Free & open source** — MIT licensed, no subscription, fully auditable code.
- ⌨️ **Works in every app** — system-wide keyboard with AZERTY / QWERTY / QWERTZ layouts.
- 🇫🇷 **French-first** — built for FR, with EN & DE; multiple Whisper sizes (tiny / base / small).
- ✨ **Native iOS feel** — iOS 26 Liquid Glass design.

## How Dictus compares

| Feature | **Dictus** | Apple Dictation | Wispr Flow | SuperWhisper | MacWhisper |
| --- | :---: | :---: | :---: | :---: | :---: |
| Price | **Free** | Built-in | Free / $15/mo | Free / $8.49/mo | Free / $6.99/mo |
| 100% offline | ✅ | ⚠️ | ❌ | ⚠️ | ⚠️ |
| Privacy-first | ✅ | ⚠️ | ❌ | ⚠️ | ⚠️ |
| Open source | ✅ | ❌ | ❌ | ❌ | ❌ |
| Custom keyboard | ✅ | ❌ | ❌ | ❌ | ❌ |
| Cross-platform | ✅ ([iOS](https://github.com/getdictus/dictus-ios) · [Android](https://github.com/getdictus/dictus-android) · [Desktop](https://github.com/getdictus/dictus-desktop)) | iOS · macOS · watchOS | iOS · macOS · Win · Android | iOS · macOS · Win | iOS · macOS |

See the full comparison on [getdictus.com](https://getdictus.com).

## Install the beta

Join via TestFlight: **[Install Dictus Beta →](https://testflight.apple.com/join/b55atKYX)**

> Requirements: iPhone 12 or later, iOS 17.0+

1. Tap the link above on your iPhone (or scan it with your camera).
2. Install TestFlight from the App Store if you don't have it.
3. Open Dictus and follow the onboarding to download a speech model.
4. Enable the keyboard: **Settings → General → Keyboard → Keyboards → Add New Keyboard → Dictus**.
5. Allow **Full Access** when prompted (required for microphone).

**Feedback:** shake your device in Dictus to send feedback via TestFlight, or open an [issue](https://github.com/getdictus/dictus-ios/issues).

## Features

- Custom iOS keyboard with AZERTY / QWERTY / QWERTZ layouts
- On-device speech recognition powered by WhisperKit (Whisper via CoreML)
- Multiple model sizes (tiny / base / small) — speed vs accuracy
- Optional Parakeet engine for alternative transcription
- Cold-start audio bridge for seamless dictation from the keyboard
- Sound feedback for recording start / stop
- iOS 26 Liquid Glass design

## Roadmap

- [x] On-device Whisper transcription (FR / EN / DE)
- [x] Custom iOS keyboard (AZERTY / QWERTY / QWERTZ)
- [x] Parakeet engine
- [ ] Smart Mode Pro — on-device LLM reformulation
- [ ] Custom vocabulary (technical terms, names)
- [ ] Searchable local transcription history
- [ ] Audio-file transcription
- [ ] Sync settings across Dictus iOS / Android / Desktop (offline-first)

Have an idea? Open a [feature request](https://github.com/getdictus/dictus-ios/issues/new) — we prioritize the most-upvoted ones.

## Building from source

```bash
git clone https://github.com/getdictus/dictus-ios.git
cd dictus-ios
open Dictus.xcodeproj
```

1. Select the **DictusApp** target and pick your device.
2. Build and run (`Cmd + R`).
3. Follow onboarding to download a speech model.
4. Enable the Dictus keyboard in Settings → General → Keyboard → Keyboards.
5. Allow **Full Access** (required for microphone).

See [DEVELOPMENT.md](DEVELOPMENT.md) for the full development guide.

### Requirements

- iOS 17.0+
- iPhone 12 or later (A14 Bionic+)
- Xcode 16+
- ~100–500 MB storage for speech models

## Architecture

Dictus is organized into three Xcode targets:

| Target | Role |
| --- | --- |
| **DictusApp** | Main app — onboarding, settings, model manager |
| **DictusKeyboard** | Keyboard extension — custom keyboard + dictation trigger |
| **DictusCore** | Shared framework — App Group storage, models, preferences |

The app and the keyboard extension communicate through an **App Group** (`group.solutions.pivi.dictus`). WhisperKit runs inside DictusApp (the keyboard extension has a ~50 MB memory limit), and an audio bridge handles cold start so dictation works seamlessly from the keyboard.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good entry points:

- `good first issue` and `help wanted` in [Issues](https://github.com/getdictus/dictus-ios/issues)
- Bug reports with TestFlight feedback (shake your device)
- Translations & locale tuning (FR is the reference; EN / DE in progress)

## Privacy

Dictus collects no user data. All speech processing happens on your device. See our [Privacy Policy](https://www.getdictus.com/en/privacy).

## Support the project

Dictus is free and will stay free. If it helps you every day, consider [supporting development](https://getdictus.com/donate) — it directly funds new features and platform support.

## Community

- 🌐 [getdictus.com](https://getdictus.com)
- 💬 [Telegram](https://t.me/getdictus)
- 🐛 [Issues](https://github.com/getdictus/dictus-ios/issues)
- 📧 [hello@getdictus.com](mailto:hello@getdictus.com)

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by argmaxinc — on-device Whisper inference
- [Parakeet](https://github.com/slingshot-ai/captions-ios) by slingshot-ai — alternative STT engine

---

<p align="center">
  <sub>Made with ❤️ by <a href="https://pivi.solutions">PIVI Solutions</a> · <a href="https://github.com/getdictus">@getdictus</a></sub>
</p>
