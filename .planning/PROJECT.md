# Dictus

## What This Is

Dictus is a free, open-source iOS keyboard app for on-device French speech-to-text dictation. Users speak into any iOS app and get accurate French transcription auto-inserted at the cursor — no subscription, no cloud, no account. Built with WhisperKit (Whisper) for speech recognition, featuring full AZERTY/QWERTY keyboard layouts and iOS 26 Liquid Glass design.

## Core Value

A user can dictate text in French in any iOS app and correct it immediately on the same keyboard without switching — no subscription, no cloud, no account.

## Requirements

### Validated

- ✓ On-device speech-to-text via WhisperKit (French primary) — v1.0
- ✓ Custom iOS keyboard extension with full AZERTY layout — v1.0
- ✓ QWERTY layout option (secondary to AZERTY) — v1.0
- ✓ Dictation works in any app via the keyboard extension — v1.0
- ✓ Microphone recording with visual/haptic feedback — v1.0
- ✓ Automatic filler word removal (handled natively by Whisper) — v1.0
- ✓ Auto-insert transcription into active text field — v1.0
- ✓ Whisper model manager (download, select, delete) — v1.0
- ✓ Onboarding flow (permissions, keyboard setup, model download) — v1.0
- ✓ Settings (model, language, keyboard layout, filler word toggle, haptic toggle) — v1.0
- ✓ iOS 26 Liquid Glass design throughout — v1.0
- ✓ Two-process architecture (keyboard triggers app for recording) — v1.0

### Active

<!-- Current milestone: v1.1 UX & Keyboard -->

- [ ] Cold start auto-return to keyboard (competitors handle this, frequent in production)
- [ ] Spacebar trackpad (long-press → cursor movement mode with haptics)
- [ ] Remove duplicate globe key, replace with emoji button
- [ ] Adaptive accent key next to N (apostrophe/accent based on context)
- [ ] Remove Apple dictation mic from keyboard (Wispr Flow does it)
- [ ] Haptic feedback on all keyboard keys
- [ ] Mic button redesign (pill shape, larger) + recording buttons pill shape
- [ ] Text prediction / autocorrect (suggestion bar)
- [ ] Accented character suggestions in suggestion bar
- [ ] Waveform animation rework (smoother, more fluid)
- [ ] Redesign test recording + recording stop screens
- [ ] Model catalog update (remove weak models, add performant ones like Parakeet v3)

### Out of Scope

- Smart modes (LLM post-processing) — deferred to v1.2+, focus on keyboard UX first
- Real-time streaming transcription — v2+ feature, current batch approach works well
- iPad support — v2+, iPhone-first
- Android port — v3+, different platform entirely
- iCloud sync — v2+, local storage sufficient for MVP
- Additional LLM providers (Claude, Groq, Ollama) — v2+, after smart modes ship
- Cloud transcription — contradicts privacy/offline identity
- Subscription / monetization — contradicts open-source positioning
- Smart Model Routing at runtime — breaks background recording, user selects model once

## Current Milestone: v1.1 UX & Keyboard

**Goal:** Bring the keyboard to Apple-level parity and polish the overall UX — cold start, trackpad, prediction, haptics, animations, and model catalog.

**Target features:**
- Cold start auto-return to keyboard
- Apple-parity keyboard (trackpad, adaptive accent, emoji, haptics, remove Apple mic)
- Text prediction / autocorrect with suggestion bar
- Mic button + recording overlay redesign (pill shapes)
- Waveform animation rework
- App screen polish (test recording, recording stop)
- Model catalog update (drop weak models, research Parakeet v3+)

## Context

Shipped v1.0 with 7,305 LOC Swift across 156 files in 4 days.
Tech stack: Swift 5.9+ / SwiftUI / WhisperKit 0.16.0+ via SPM.
Architecture: Two-process (keyboard extension + main app via Darwin notifications + URL scheme).
App Group: `group.com.pivi.dictus` for all cross-process data sharing.
Keyboard extension memory limit: ~50MB (tiny/base/small models only in extension).

Known remaining issues:
- Cold start auto-return to keyboard is the top priority for next milestone
- Design files duplicated between DictusApp and DictusKeyboard (6 files, manual sync)
- SmartModelRouter exists but intentionally bypassed

## Constraints

- **Memory**: Keyboard extensions limited to ~50MB RAM
- **Permissions**: Microphone in keyboard requires Full Access enabled
- **Extension limitations**: No `UIApplication.shared` in keyboard extensions
- **Data sharing**: All shared data via App Group (`group.com.pivi.dictus`)
- **Minimum target**: iOS 16.0, iPhone 12+ (A14 Bionic) recommended
- **Stack**: Swift 5.9+ / SwiftUI / WhisperKit via SPM
- **License**: MIT — fully open source

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| WhisperKit over whisper.cpp | Native Swift, Core ML + Metal optimized, maintained by Argmax | ✓ Good — accurate French STT, easy integration |
| AZERTY as default layout | Primary user is French, main competitive advantage | ✓ Good — key differentiator |
| Liquid Glass from day one | Design is a project motivation | ✓ Good — premium look achieved |
| Keyboard without autocorrect in MVP | Text prediction too complex for first release | ✓ Good — shipped faster |
| Smart modes deferred | Core STT must work first | ✓ Good — solid foundation |
| Small model as default | Best balance of speed and French accuracy | ✓ Good — fits memory constraints |
| Two-process architecture | Keyboard 50MB limit prevents loading Whisper models | ✓ Good — works reliably |
| Darwin notifications for IPC | Lightweight cross-process signaling | ✓ Good — <100ms latency |
| Audio background mode | Keep recording alive when user returns to previous app | ✓ Good — seamless UX |
| DUX-02 (undo button) dropped | User decided manual select+delete is sufficient | ✓ Good — simpler UX |
| STT-04 (smart routing) dropped | Runtime model switching breaks background recording | ✓ Good — stability over feature |
| Design file duplication | DictusKeyboard can't import DictusApp code, DictusCore can't have UIKit | ⚠️ Revisit — manual sync burden |
| FillerWordFilter removed | Whisper model handles filler removal natively | ✓ Good — less code |

---
*Last updated: 2026-03-07 after v1.1 milestone start*
