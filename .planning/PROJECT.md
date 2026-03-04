# Dictus

## What This Is

Dictus is a free, open-source iOS keyboard app that lets users dictate text into any application using on-device speech recognition (WhisperKit/Whisper). It's a replacement for Super Whisper and Wispr Flow — built for French-speaking users who need an AZERTY keyboard with a quality typing experience alongside voice dictation. Embraces iOS 26 Liquid Glass design language from day one.

## Core Value

A user can dictate text in French in any iOS app and correct it immediately on the same keyboard without switching — no subscription, no cloud, no account.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] On-device speech-to-text via WhisperKit (French primary, English secondary)
- [ ] Custom iOS keyboard extension with full AZERTY layout
- [ ] Dictation works in any app via the keyboard extension
- [ ] Microphone recording with visual/haptic feedback
- [ ] Automatic filler word removal (euh, hm, voilà...)
- [ ] Auto-insert transcription into active text field
- [ ] Undo capability for inserted text
- [ ] Transcription preview/edit zone in the keyboard
- [ ] Whisper model manager (download, select, delete)
- [ ] Onboarding flow (permissions, keyboard setup, model download)
- [ ] Settings (model, language, keyboard layout, filler word toggle)
- [ ] iOS 26 Liquid Glass design throughout
- [ ] QWERTY layout option (secondary to AZERTY)

### Out of Scope

- Text prediction / autocorrect — too complex for MVP, will be added post-MVP
- Smart modes (LLM post-processing) — v1+ feature, after core STT is solid
- Real-time streaming transcription — v2 feature
- iPad support — v2+
- Android port — v3
- iCloud sync — v2+
- Additional LLM providers (Claude, Groq, Ollama) — v2+

## Context

- **Inspiration**: [Handy](https://handy.computer/) (macOS, open source, offline STT) — Dictus is the iOS equivalent
- **Pain point**: Super Whisper's keyboard is QWERTY-only, has no autocorrect, and requires switching keyboards to correct text — frustrating for French AZERTY users
- **User profile**: Pierre uses dictation primarily to avoid typing — messaging AI agents (Claude, ChatGPT, OpenFlow bot), SMS, and emails. Dictates 90%+ in French with occasional English technical terms
- **Learning goal**: First Swift/iOS project — the development process itself is a goal (learning SwiftUI, iOS architecture, keyboard extensions)
- **Design motivation**: Liquid Glass (iOS 26) is a personal passion — the app should look and feel premium despite being free

## Constraints

- **Memory**: Keyboard extensions are limited to ~50MB RAM — only tiny/base/small Whisper models can load in the extension
- **Permissions**: Microphone in keyboard requires `RequestsOpenAccess = true` and user enabling "Full Access" in iOS Settings
- **Extension limitations**: No access to `UIApplication.shared` in keyboard extensions
- **Data sharing**: All shared data between app and keyboard must go through App Group (`group.com.pivi.dictus`)
- **Minimum target**: iOS 16.0, iPhone 12+ (A14 Bionic) recommended
- **Stack**: Swift 5.9+ / SwiftUI / WhisperKit via SPM
- **License**: MIT — fully open source

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| WhisperKit over whisper.cpp | Native Swift, Core ML + Metal optimized, maintained by Argmax | — Pending |
| AZERTY as default layout | Primary user is French, main competitive advantage over Super Whisper | — Pending |
| Liquid Glass from day one | Design is a project motivation, not an afterthought | — Pending |
| Keyboard without autocorrect in MVP | Text prediction is the most complex feature (~2-3 sprints alone), ship basic first | — Pending |
| Smart modes deferred to v1+ | Core STT + good keyboard must work first, LLM is a nice-to-have | — Pending |
| Small model as default | Best balance of speed and French accuracy, fits in extension memory | — Pending |

---
*Last updated: 2026-03-04 after initialization*
