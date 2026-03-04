# Features Research

*Last updated: 2026-03-04*

## Competitors Analyzed

- **Super Whisper** (iOS + macOS) — YC-backed, subscription ($8.49/mo or $84.99/yr), offline + cloud modes, LLM post-processing
- **Wispr Flow** (iOS + macOS + Windows) — cloud-only, subscription ($15/mo, 2,000 words/wk free), 97%+ accuracy claim
- **WhisperBoard** (iOS) — free, open source, standalone transcription app (NOT a keyboard extension)
- **Whisper Notes** (iOS) — $4.99 one-time, offline, standalone app (NOT a keyboard extension)
- **Willow** (iOS) — YC S25, full QWERTY keyboard + voice, context-aware formatting, enterprise-focused
- **Apple built-in dictation** — free, ~60s limit, accuracy issues in iOS 18, English-centric

---

## Table Stakes

Features users expect as a baseline. Missing any of these is a reason to leave.

### 1. Universal dictation — works in any app
**Complexity**: High
The entire value proposition. Without this, it's just a note-taking app. Requires a functional iOS keyboard extension with Full Access. This is technically non-trivial: Apple's keyboard extension sandbox is strict, microphone access requires `RequestsOpenAccess = true`, and the extension must stay under ~50-60MB RAM. All competitors that are keyboard-based (Super Whisper, Wispr Flow, Willow) solve this first.

### 2. Accuracy that beats Apple's built-in dictation
**Complexity**: Medium (WhisperKit handles the heavy lifting)
Apple's dictation is notoriously inconsistent — users frequently complain about nonsense word substitutions, random punctuation, and degraded accuracy after iOS 18. Whisper models (even small) reliably outperform it. This is table stakes because users already have Apple's dictation for free; if a third-party tool isn't meaningfully better, there's no reason to switch keyboards.

### 3. Low-latency transcription (perceptually fast)
**Complexity**: Medium
Users abandon tools that feel slow. Acceptable latency is 1-3 seconds for a short utterance on-device. WhisperKit's Core ML + Metal pipeline achieves this on A14+ chips with small/base models. The tiny model is faster but significantly less accurate in French — small model is the right default.

### 4. French language support with acceptable accuracy
**Complexity**: Low (Whisper is multilingual by design)
Super Whisper's iOS keyboard is QWERTY-only — this is the primary pain point the project solves. French support at the model level is already built into Whisper. The differentiator is that competitors either don't support French well or require QWERTY. This is table stakes *for French users* specifically; for English users it would be "just works."

### 5. Filler word removal
**Complexity**: Low-Medium
Every competitor removes filler words (um, uh, like, "euh", "hm", "voilà" for French). It's expected. A rule-based approach (word list filter) is simple but misses context. A post-processing LLM is accurate but adds latency and complexity. For MVP, a curated French + English filler word list is sufficient and fast.

### 6. Automatic punctuation
**Complexity**: Low (Whisper produces punctuation natively)
Whisper models output punctuated text by default. This is a baseline expectation — Apple's dictation frequently fails at this, which is a known frustration. No additional implementation needed beyond what WhisperKit provides.

### 7. Transcription preview before insertion
**Complexity**: Medium
Users need to see what was transcribed before it lands in the text field, especially when accuracy matters (messaging, emails). All mature competitors show a preview zone. This is also practically necessary given the edit loop: dictate → review → correct → insert. WhisperBoard and Whisper Notes both default to review-before-insert.

### 8. Undo inserted text
**Complexity**: Low-Medium
If the transcription is wrong and the user inserts it anyway, they need a way to remove the whole block at once — not character-by-character backspace. iOS keyboard APIs support this via `deleteBackward` and `textDocumentProxy`. Table stakes because the alternative (manually selecting and deleting inserted text) breaks the keyboard flow entirely.

### 9. Microphone visual feedback during recording
**Complexity**: Low
A clear recording indicator (waveform animation, level meter, or simple pulsing icon) is expected. Without it, users don't know if the mic is active. Every competitor provides this. Haptic feedback on start/stop is a bonus but considered expected on iOS.

### 10. Onboarding for keyboard + permissions setup
**Complexity**: Medium
iOS keyboard setup is genuinely confusing (Settings > General > Keyboard > Keyboards > Add New Keyboard, then enable Full Access). Without guided onboarding, most users will fail setup and leave a 1-star review. All serious keyboard apps provide step-by-step onboarding. Permissions needed: microphone (required for recording), Full Access (required to use microphone in extension).

### 11. Model download and management
**Complexity**: Medium
WhisperKit models are not bundled — they must be downloaded. Users need to understand which model to download (tiny is fast but poor French accuracy, small is the right balance, medium is too large for the extension at ~50MB). An in-app model browser with size/speed/accuracy tradeoffs shown clearly is expected by power users.

---

## Differentiators

Features where Dictus can win against competitors.

### 1. AZERTY keyboard layout
**Complexity**: Medium
**Why it wins**: Super Whisper's iOS keyboard is QWERTY-only. Wispr Flow and Willow are also QWERTY-only on iOS. For French users, switching from AZERTY to QWERTY to correct a dictation error, then back, is enough friction to abandon the tool. Dictus ships AZERTY as default with QWERTY as secondary. This is a direct response to the stated primary pain point and has no competitor parity on iOS today.
**Dependency**: Full keyboard implementation (layout engine, key rendering, text input proxy).

### 2. Fully on-device, no account, no subscription
**Complexity**: Low (architecture decision, not implementation complexity)
**Why it wins**: Wispr Flow ($15/mo, cloud-required), Super Whisper ($8.49/mo or $84.99/yr), Willow (subscription model). Whisper Notes charges $4.99 once but is not a keyboard. WhisperBoard is free and open source but is also not a keyboard. Dictus is free + open source + offline-only — a genuinely different position. Privacy-conscious users and users burned by SaaS pricing churn respond to this.
**Dependency**: WhisperKit on-device model, no network calls in transcription path.

### 3. Inline correction in the same keyboard (no context switching)
**Complexity**: High
**Why it wins**: The Super Whisper iOS flow requires switching keyboards to correct text — the primary stated frustration in PROJECT.md. Dictus keeps dictation, preview, and correction in the same keyboard view. The user never needs to switch input methods. This requires a well-designed keyboard layout that shows a transcription edit zone while remaining usable as a standard keyboard.
**Dependency**: Custom AZERTY keyboard, transcription preview zone, text editing within the keyboard UI.

### 4. iOS 26 Liquid Glass design
**Complexity**: Medium (once iOS 26 SDK APIs are available)
**Why it wins**: No competitor will adopt iOS 26 design from day one — it takes time for established apps to update. Dictus is purpose-built for iOS 26 and can set the visual standard for voice keyboard apps. This is a meaningful differentiator for users who care about fit-and-finish and an explicit personal project motivation.
**Dependency**: iOS 26 SDK, SwiftUI Liquid Glass components, no backwards compatibility to worry about pre-iOS 26.

### 5. French-first, not French-as-an-afterthought
**Complexity**: Low-Medium
**Why it wins**: Competitors support French, but none are tuned for it. French filler words ("euh", "bah", "voilà", "quoi"), French punctuation conventions (space before `:`), and French-specific corrections (accentuation on proper nouns, contractions) are all edge cases that English-first apps handle poorly. A curated French filler word list and correct punctuation handling differentiates the experience for native speakers.
**Dependency**: Filler word list, optional post-processing rules.

### 6. Open source / MIT licensed
**Complexity**: Low (no implementation complexity — it's a licensing decision)
**Why it wins**: Super Whisper and Wispr Flow are closed source. Whisperboard is open source but not a keyboard. An open-source iOS voice keyboard lets developers fork, audit privacy, and contribute. Builds trust with privacy-sensitive users. Also enables community-driven AZERTY improvements for regional variants (Belgian, Swiss, Canadian French).
**Dependency**: None — this is a distribution choice.

---

## Anti-Features

Things to deliberately NOT build, with reasoning.

### 1. Cloud transcription / server-side processing
**Reasoning**: Defeats the privacy advantage, adds infrastructure cost, creates a subscription dependency, and introduces latency from network round-trips. Wispr Flow requires cloud and charges $15/mo for it. Dictus's entire identity is "no cloud, no account, no subscription." Adding cloud transcription as an optional mode confuses the value proposition and splits the codebase.

### 2. Text prediction / autocorrect (in MVP)
**Reasoning**: Text prediction is the most complex feature in any keyboard — Apple has entire teams dedicated to it, and third-party implementations require large language model integration, n-gram dictionaries, and per-user learning databases. It's 2-3 sprints of work minimum. Apple's native autocorrect already exists in every iOS text field through the system text input system — Dictus does not need to replicate it. This is explicitly deferred to post-MVP in PROJECT.md.

### 3. LLM post-processing / "smart modes" (in MVP)
**Reasoning**: Super Whisper's killer feature on macOS is LLM post-processing (GPT-4/Claude to rewrite dictated text). This is complex to implement correctly, adds API cost or model size, and creates a dependency on either a server or a large local LLM. The core STT pipeline must be reliable first. Smart modes are v1+ and the on-device LLM story on iOS is still immature (limited context windows, slow inference for large models in extensions). Do not build this until the base keyboard is excellent.

### 4. Real-time streaming transcription
**Reasoning**: Streaming (word-by-word as you speak) is visually impressive but technically demanding: it requires a streaming-compatible Whisper inference path, careful buffer management, and significantly more CPU during recording. WhisperKit does support streaming but it's a harder implementation path. The user experience benefit is real but the marginal value over "record then transcribe in 1-2 seconds" does not justify the complexity for MVP. Deferred to v2.

### 5. iCloud sync / cross-device history
**Reasoning**: Dictation history stored in iCloud requires entitlements, CloudKit setup, conflict resolution, and user data policies. The keyboard extension already has severe limitations — adding iCloud sync adds another axis of failure. The primary use case is ephemeral: dictate, insert, done. History is a nice-to-have but not a reason users adopt a voice keyboard. Deferred to v2+.

### 6. iPad or multi-window support
**Reasoning**: iPad keyboards have different layout constraints, split-screen adds edge cases, and the primary user profile is iPhone. Supporting iPad doubles the QA surface for a solo developer learning Swift. Deferred to v2+.

### 7. Multiple LLM provider integrations (in MVP)
**Reasoning**: Claude, Groq, Ollama — adding provider choice is useful eventually but creates a settings sprawl that confuses new users and multiplies the test surface. If smart modes ship in v1+, start with one provider and add others based on user demand. The v1 question is "does LLM post-processing improve the experience?" not "which LLM is best?"

### 8. Subscription model or any monetization
**Reasoning**: The explicit positioning is free + open source. Adding a subscription — even optional — changes the nature of the project, creates support obligations, and undermines the trust advantage over Wispr Flow and Super Whisper. If monetization is ever needed (App Store hosting costs, etc.), a one-time tip/donation model aligns better with the project's character.

---

## Feature Dependencies

Which features depend on which — relevant for sequencing development.

```
WhisperKit model download (app)
  └─ On-device transcription (core pipeline)
       ├─ Filler word removal (post-process step, trivial once transcription works)
       ├─ Automatic punctuation (native in Whisper output, no extra work)
       └─ Transcription result (feeds everything below)

iOS keyboard extension (Full Access + microphone)
  ├─ AZERTY layout (key rendering, text input proxy)
  │    └─ QWERTY layout option (secondary, same architecture)
  ├─ Microphone recording in extension (requires Full Access)
  │    ├─ Visual/haptic recording feedback (UI layer on top of recording)
  │    └─ Transcription trigger → WhisperKit pipeline (via App Group shared memory)
  ├─ Transcription preview zone (UI component inside keyboard)
  │    └─ Inline edit before insert (text editing within preview zone)
  └─ Auto-insert into active text field (textDocumentProxy.insertText)
       └─ Undo inserted text (textDocumentProxy.deleteBackward x N)

App Group (group.com.pivi.dictus)
  └─ Shared data channel between app and extension
       ├─ Model selection setting
       ├─ Language preference
       └─ Filler word toggle

Onboarding flow (app)
  ├─ Microphone permission request
  ├─ Full Access setup instructions
  └─ Model download trigger → model manager

Settings (app)
  ├─ Model selection → model manager
  ├─ Language toggle (French / English)
  ├─ Keyboard layout toggle (AZERTY / QWERTY)
  └─ Filler word toggle

iOS 26 Liquid Glass design
  └─ Applied as UI layer on top of all components above — no functional dependency
       but must be considered from the first component built to avoid rework
```

### Critical path for MVP

1. **WhisperKit integration** (app target) — proves transcription works on device
2. **Keyboard extension scaffold** (extension target + App Group) — proves the pipe exists
3. **Microphone recording in extension** — proves Full Access + mic works end-to-end
4. **AZERTY keyboard layout** — core differentiator, needed before any user testing
5. **Transcription preview + insert** — completes the basic dictation loop
6. **Filler word removal** — trivial once pipeline works, high perceived quality impact
7. **Onboarding + model manager** — required for any user beyond the developer
8. **Settings** — model/language/layout preferences
9. **Liquid Glass polish** — applied throughout but non-blocking on core loop

Undo and QWERTY layout are high-value but can ship in the first patch after the core MVP loop is working.
