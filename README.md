# Dictus

**Free, open-source iOS keyboard for voice dictation.**

On-device speech recognition via [WhisperKit](https://github.com/argmaxinc/WhisperKit) — no server, no account, no subscription.

## Features

- Custom iOS keyboard with full AZERTY/QWERTY support
- 100% on-device transcription (WhisperKit / Whisper)
- Filler word removal (euh, hm, um...)
- Smart modes with LLM post-processing (bring your own OpenAI API key)
- iOS 26 Liquid Glass design

## Requirements

- iOS 16.0+
- iPhone 12 or later (A14 Bionic recommended)
- Xcode 16+

## Getting Started

```bash
git clone https://github.com/Pivii/dictus.git
cd dictus
open Dictus.xcodeproj
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for the full development guide.

## License

MIT — see [LICENSE](LICENSE) for details.
