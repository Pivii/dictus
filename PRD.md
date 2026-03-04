# Dictus — Product Requirements Document

> **Version** 1.1 · Draft  
> **Date** March 2026  
> **Author** Pierre / PIVI Solutions  
> **Status** Ready for development  
> **Stack** Swift · SwiftUI · WhisperKit · iOS 26  
> **Licence** MIT (open source)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Context & Market Analysis](#2-context--market-analysis)
3. [Product Goals](#3-product-goals)
4. [Target Users](#4-target-users)
5. [Technical Architecture](#5-technical-architecture)
6. [V1 Features — MVP](#6-v1-features--mvp)
7. [V1+ Features — Advanced](#7-v1-features--advanced)
8. [Dictation Modes](#8-dictation-modes)
9. [Design — Liquid Glass](#9-design--liquid-glass)
10. [Roadmap](#10-roadmap)
11. [Distribution & Open Source](#11-distribution--open-source)
12. [Risks & Mitigations](#12-risks--mitigations)
13. [References](#13-references)

---

## 1. Executive Summary

**Dictus** (*latin: "ce qui a été dit"*, past participle of *dicere*) is a free, open-source iOS app that enables voice dictation in any application through a custom iOS keyboard. It uses Whisper via WhisperKit for fully on-device speech recognition — no server, no account, no subscription required for the core feature.

### The gap in the market

| | Free | On-device | Custom keyboard | AZERTY support | Open source |
|---|---|---|---|---|---|
| Wispr Flow | ❌ ($12/mo) | ❌ Cloud | ✅ | ❌ | ❌ |
| Super Whisper | ❌ Paid | ⚠️ Partial | ✅ | ❌ QWERTY only | ❌ |
| WhisperBoard | ✅ | ✅ | ❌ | ❌ | ✅ |
| Whisper Notes | ❌ ($4.99) | ✅ | ❌ | ❌ | ❌ |
| **Dictus** | **✅** | **✅** | **✅** | **✅** | **✅** |

> **Dictus is the only iOS app that checks all five boxes.**

### Core philosophy

Two modes, clearly separated:

- **STT mode** — pure speech-to-text, word for word, filler words cleaned up automatically. No internet required.
- **Smart modes** — STT + LLM post-processing (reformat as email, summarize, rewrite for Slack, etc.). Requires an OpenAI API key configured by the user.

---

## 2. Context & Market Analysis

### 2.1 Name & origin

**Dictus** — latin past participle of *dicere* = "to say". Literally: *"that which has been said"*. No existing iOS app uses this name. Available as a GitHub repo name and likely as `dictus.app`.

### 2.2 Inspiration

The [Handy](https://github.com/cjpais/Handy) project is a desktop (macOS/Windows/Linux) open-source, offline speech-to-text app. Dictus draws philosophical inspiration from it but is an independent creation for iOS. Handy's MIT licence fully permits this approach.

### 2.3 Key UX problems Dictus solves

**Problem 1 — No keyboard access after transcription (Wispr Flow)**  
Wispr Flow's keyboard has no standard keyboard layout. After transcription, if the result is imperfect, the user must switch keyboards via the globe button to correct the text — a jarring, friction-heavy experience.

**Problem 2 — QWERTY only (Super Whisper)**  
Super Whisper's keyboard is hardcoded in QWERTY. French users on AZERTY have to mentally remap every key, making quick corrections painful.

**Problem 3 — No text prediction**  
Neither Super Whisper nor Wispr Flow offer text prediction/autocorrect in their keyboard, unlike the native Apple keyboard. Dictus will include this.

**Problem 4 — No intelligent modes**  
Existing free tools do raw transcription only. There is no open-source app that lets users define custom LLM-powered dictation modes (email, Slack, notes) with their own API key.

### 2.4 Competitor breakdown

**Wispr Flow** — Custom keyboard ✅, cloud-based ❌, freemium $12/mo, iOS slightly inferior to macOS, no AZERTY  
**Super Whisper** — Custom keyboard ✅, partial on-device, paid, QWERTY only  
**WhisperBoard** — 100% on-device ✅, free ✅, open source ✅, no keyboard extension ❌  
**Whisper Notes** — 100% on-device ✅, $4.99 one-time, no keyboard extension ❌

---

## 3. Product Goals

### 3.1 Vision

Let any iOS user — French or English speaking — dictate text into any app, correct it instantly without switching keyboards, and optionally reformat it with AI, all without a subscription.

### 3.2 V1 Success metrics

- Transcription in under 2 seconds for 10 seconds of audio (tiny/base model)
- Error rate < 5% on natural French or English with the small model
- Text auto-inserted immediately after transcription, with undo available
- Zero audio data leaving the device (STT mode)
- AZERTY layout working correctly with French autocorrect suggestions
- Compatible iPhone 12 and above (A14 Bionic minimum recommended)

---

## 4. Target Users

| Persona | Description |
|---|---|
| **French professional** | Works in French, AZERTY keyboard, dictates messages and emails daily. Was frustrated by Super Whisper's QWERTY-only keyboard. |
| **Bilingual user** | Switches between French and English. Wants Whisper to auto-detect language without manual switching. |
| **Developer / power user** | Privacy-conscious, wants open source, brings their own OpenAI API key for smart modes. |
| **Wispr Flow / Super Whisper migrant** | Knows the concept, looking for a free, offline alternative with a better keyboard experience. |

---

## 5. Technical Architecture

### 5.1 Xcode project structure

```
Dictus/
├── DictusApp/                    # Main app target
│   ├── Onboarding/               # First-launch flow
│   ├── Settings/                 # Model, keyboard layout, language, API keys
│   ├── ModelManager/             # Download, select, delete Whisper models
│   ├── ModeEditor/               # Create and edit dictation modes
│   └── TestDictation/            # In-app dictation test screen
│
├── DictusKeyboard/               # Keyboard Extension target
│   ├── KeyboardView.swift        # SwiftUI keyboard layout (AZERTY/QWERTY)
│   ├── MicButton.swift           # Mic button + state machine
│   ├── TranscriptionPreview.swift# Preview area + edit zone
│   ├── AudioRecorder.swift       # AVFoundation audio capture
│   ├── TranscriptionEngine.swift # WhisperKit integration
│   ├── LLMProcessor.swift        # OpenAI post-processing for smart modes
│   ├── ModeSelector.swift        # Mode switcher UI in keyboard
│   └── TextInserter.swift        # textDocumentProxy insertion
│
└── DictusCore/                   # Shared framework (App Group)
    ├── ModelStore.swift           # Model path resolution
    ├── ModeStore.swift            # Dictation modes persistence
    ├── UserPreferences.swift      # Shared UserDefaults suite
    └── AudioUtils.swift           # PCM conversion helpers
```

### 5.2 Tech stack

| Component | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI framework | SwiftUI + UIKit (keyboard extension) |
| Speech recognition | WhisperKit (Argmax) — Core ML + Metal |
| Audio capture | AVFoundation |
| LLM post-processing | OpenAI API (GPT-4o) — optional, user-provided key |
| Keyboard layout | Custom SwiftUI keyboard (AZERTY/QWERTY/QWERTZ) |
| Text prediction | UILexicon (system dictionary) + custom n-gram predictor |
| Data sharing | App Group (main app ↔ keyboard extension) |
| Minimum iOS | iOS 16.0 |
| Minimum device | iPhone 12 (A14 Bionic) recommended |
| Package manager | Swift Package Manager |

### 5.3 Key iOS constraints

> ⚠️ **Extension memory limit (~50MB)**  
> Keyboard extensions have a strict RAM limit. Medium and large Whisper models cannot be loaded directly in the extension. Dictus restricts the keyboard to tiny/base/small models. Larger models can be used via the main app's test screen only.

> ⚠️ **Full Access required**  
> Microphone access in a keyboard extension requires `RequestsOpenAccess = true` in Info.plist. The user must enable "Allow Full Access" in iOS Settings. Onboarding guides this step explicitly.

> ⚠️ **Text prediction complexity**  
> Building a full AZERTY/QWERTY keyboard with native-quality text prediction is the most complex feature in the project (~2-3 sprints alone). `UILexicon` provides the system word list, but predictive suggestions require a custom implementation. This is scoped as V1+ (post-MVP), not MVP.

> ⚠️ **LLM calls from extension**  
> The keyboard extension can make network calls if Full Access is enabled. OpenAI API calls for smart modes will be made directly from the extension using the user's stored API key (App Group keychain).

### 5.4 WhisperKit integration

```swift
// Package.swift
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")

// Transcription in keyboard extension
import WhisperKit

let whisper = try await WhisperKit(modelFolder: sharedModelPath)
let result = try await whisper.transcribe(audioArray: pcmBuffer)
let cleaned = FillerWordRemover.clean(result?.text ?? "")
// → auto-insert or pass to LLM depending on active mode
```

---

## 6. V1 Features — MVP

### 6.1 Main App

#### Onboarding (first launch)
1. Welcome screen — concept in 3 slides (what Dictus does, why it's free, why it's private)
2. Microphone permission request
3. Keyboard layout selection: **AZERTY** (default) / QWERTY / QWERTZ
4. Step-by-step instructions to add keyboard in iOS Settings (deep-link shortcut button)
5. Instructions to enable "Full Access"
6. Model download — `small` multilingual by default (best FR/EN balance)
7. Test screen — live dictation test with the configured keyboard

#### Model Manager

| Model | Size | Speed | Accuracy FR/EN |
|---|---|---|---|
| tiny | ~75 MB | ⚡⚡⚡⚡ | ★★☆☆ |
| base | ~140 MB | ⚡⚡⚡ | ★★★☆ |
| small *(default)* | ~460 MB | ⚡⚡ | ★★★★ |
| medium | ~1.5 GB | ⚡ | ★★★★★ |
| large-v3-turbo | ~1.6 GB | ⚡⚡ | ★★★★★ |

- Download from Hugging Face via WhisperKit
- Storage indicator per model
- Delete unused models
- Active model persisted in App Group UserDefaults

#### Settings
- Active Whisper model
- Transcription language: **Auto-detect** (default) / Français / English
- Keyboard layout: **AZERTY** / QWERTY / QWERTZ
- Filler word removal: on (default) / off
- Auto-insert after transcription: on (default) / off
- Haptic feedback: on / off
- OpenAI API key (for smart modes) — stored in App Group Keychain

### 6.2 Keyboard Extension — MVP

#### Layout
The Dictus keyboard is a full standard keyboard (AZERTY/QWERTY/QWERTZ based on settings) with an additional top row:

```
┌─────────────────────────────────────────────────────┐
│  [MODE]  [transcription preview / edit zone]  [✓]  │
├────────────────────────┬────────────────────────────┤
│                        │                            │
│   FULL AZERTY/QWERTY   │                            │
│   keyboard layout      │         🎤                 │
│   with suggestions     │    (large mic button)      │
│   bar on top           │                            │
│                        │                            │
├────────────────────────┴──────────────┬─────────────┤
│  space                                │  return  🌐 │
└───────────────────────────────────────┴─────────────┘
```

> **Note on suggestions bar**: text prediction requires UILexicon + custom predictor. Scoped as V1+, not MVP. The keyboard layout itself ships in MVP without suggestions.

#### Dictation flow (MVP)
1. User opens any app with a text field → switches to Dictus via globe key
2. Taps mic button → recording starts (visual + haptic feedback, waveform animation)
3. User speaks in French or English (auto-detected)
4. Taps mic again to stop → WhisperKit transcribes on-device
5. Filler words removed automatically ("euh", "hm", "voilà"...)
6. **Auto-insert**: text inserted directly into the active field via `textDocumentProxy`
7. Transcription also appears in the preview zone for review
8. User can edit inline using the full AZERTY/QWERTY keyboard below
9. **Undo** available: shake to undo or dedicated undo button removes the inserted text

#### Mode selector (MVP — STT only)
- A `[MODE]` button in the top-left of the keyboard
- MVP ships with one mode: **STT** (pure transcription, no LLM)
- Additional smart modes appear here once configured in Settings

---

## 7. V1+ Features — Advanced

*Post-MVP, same major version.*

### 7.1 Full keyboard with text prediction

Building a native-quality keyboard is the most complex feature. Approach:

- AZERTY / QWERTY / QWERTZ layouts implemented in SwiftUI
- `UILexicon` for system word list access (respects user's personal dictionary)
- Custom bigram/trigram predictor trained on common FR + EN word sequences
- Suggestion bar above keyboard (3 suggestions, tappable)
- Autocorrect for common typos
- Support for accented characters (é, è, ê, à, ù...) via long-press on AZERTY

### 7.2 Smart Model Routing *(inspiré de [Melvynx/Parler](https://github.com/Melvynx/Parler))*

#### Le problème

Les modèles rapides (tiny/base) sont excellents sur les vocaux courts, mais sur les enregistrements longs contenant du **code-switching FR/EN** (ex : parler en français en mentionnant des termes techniques anglais), ils peuvent basculer leur langue de décodage vers l'anglais et transcrire tout le reste en anglais.

Exemple typique : *"j'ai un bug dans mon `useEffect`, en fait le `setState` il s'appelle deux fois parce que..."* — un modèle léger peut décider que c'est de l'anglais et tout transcrire en anglais.

#### La solution — Adaptive Model Switching

Inspiré de la feature de conditionnement de modèle ajoutée par Melvynx dans son fork de Handy/Parler. Adaptée aux contraintes iOS.

**Principe** : Dictus mesure la durée de l'enregistrement *avant* de lancer la transcription (l'audio est déjà bufferisé), et choisit le modèle approprié :

```
durée < seuil → modèle rapide (tiny/base) = résultat quasi-instantané
durée ≥ seuil → modèle précis (small)     = meilleure résistance au code-switching
```

**Avantage iOS vs desktop** : sur desktop, il faut détecter en temps réel. Sur iOS, l'enregistrement est entièrement bufferisé avant la transcription — le switch est donc propre et sans interruption.

#### Logique de routing complète

```
┌─ Durée < seuil ──────────────────────────────────────────┐
│  → modèle rapide configuré (défaut : tiny ou base)       │
│  → résultat en < 1 seconde                               │
└──────────────────────────────────────────────────────────┘

┌─ Durée ≥ seuil ──────────────────────────────────────────┐
│  → modèle précis configuré (défaut : small)              │
│  + si langue = Français (pas Auto) → langue forcée sur   │
│    le modèle → résout le bug de code-switching           │
└──────────────────────────────────────────────────────────┘
```

La **détection de langue explicite** est la contribution Dictus par rapport à la version Parler : si l'utilisateur a sélectionné "Français" dans les settings (pas "Auto-detect"), on force `language: "fr"` sur WhisperKit même sur les vocaux longs. Ce paramètre seul résout 90% du bug de code-switching, sans avoir besoin du modèle plus gros.

#### Settings

Dans Settings → Transcription :

| Setting | Options | Défaut |
|---|---|---|
| Smart Model Routing | Activé / Désactivé | Activé |
| Seuil de durée | 5s / 10s / 20s / 30s | 10s |
| Modèle court | tiny / base | base |
| Modèle long | base / small | small |

#### Feedback UX

Quand le modèle long est sélectionné automatiquement, un indicateur subtil dans la zone preview l'indique :
- Icône de chargement légèrement différente (shimmer plus lent = modèle plus lourd)
- Optionnel : badge "précis" qui s'affiche 1s puis disparaît

#### Implémentation Swift

```swift
// DictusCore/ModelRoutingConfig.swift

struct ModelRoutingConfig: Codable {
    var isEnabled: Bool = true
    var durationThreshold: TimeInterval = 10.0  // secondes
    var fastModel: WhisperModelSize = .base
    var accurateModel: WhisperModelSize = .small
}

// DictusKeyboard/TranscriptionEngine.swift

func resolveModel(
    audioDuration: TimeInterval,
    routing: ModelRoutingConfig,
    forcedLanguage: String?  // nil = auto-detect
) -> (model: WhisperModelSize, language: String?) {
    let useAccurate = routing.isEnabled && audioDuration >= routing.durationThreshold
    let model = useAccurate ? routing.accurateModel : routing.fastModel
    // Si langue forcée → toujours passer le paramètre language à WhisperKit
    // indépendamment du modèle choisi. Ça résout le bug FR/EN seul.
    return (model, forcedLanguage)
}
```



- Last 20 transcriptions stored locally (App Group)
- Accessible from the keyboard via a swipe-up gesture or dedicated button
- Tap any past transcription to re-insert it
- Auto-cleared after 7 days (configurable)

### 7.3 Smart modes with LLM

See [Section 8 — Dictation Modes](#8-dictation-modes) for full spec.

---

## 8. Dictation Modes

Dictus introduces a **mode system** that separates raw transcription from AI-enhanced dictation.

### 8.1 Architecture

```
User speaks
    ↓
WhisperKit (on-device)
    ↓
Raw transcript
    ↓
Filler word removal (always)
    ↓
[if STT mode]          [if Smart mode]
Insert directly    →   OpenAI GPT-4o
                       (user's API key)
                            ↓
                       Formatted output
                            ↓
                       Insert into field
```

### 8.2 Default modes (pre-installed)

| Mode | Icon | What it does |
|---|---|---|
| **STT** | 🎤 | Pure transcription, filler words removed. No internet. |
| **Email** | ✉️ | Reformats dictation as a clean, professional email. Adds greeting/sign-off. |
| **SMS / iMessage** | 💬 | Keeps casual tone, short sentences, appropriate punctuation. |
| **Note** | 📝 | Structures dictation as bullet points or a clean paragraph. |
| **Slack** | ⚡ | Concise, removes filler, keeps informal professional tone. |

### 8.3 Custom modes

Users can create their own modes in Settings → Modes → +:

```
Mode name:    [________________]
Icon:         [emoji picker]
System prompt:
┌────────────────────────────────────────────────┐
│ You are a professional assistant. Rewrite the  │
│ following dictation as a formal legal memo...  │
└────────────────────────────────────────────────┘
Language output: [Auto / FR / EN]
Provider:        OpenAI GPT-4o (v1 only)
```

### 8.4 API key management

- User enters their OpenAI API key in Settings → API Keys
- Stored in App Group Keychain (never in UserDefaults or plain storage)
- STT mode never uses the API key — works fully offline
- Smart modes are greyed out until an API key is configured
- Clear warning shown: "Your API key is stored locally on your device only"

### 8.5 Mode selector in keyboard

- `[MODE]` button in top-left of keyboard
- Tap → bottom sheet slides up with mode list (Liquid Glass style)
- Active mode shown as pill label next to the mic button
- Last used mode remembered per-session

### 8.6 V2+ providers (post-MVP)

Future versions will add:
- Anthropic Claude (claude-sonnet-4-6)
- Groq (ultra-fast inference)
- Ollama (local LLM, fully offline smart modes)
- Any OpenAI-compatible endpoint (custom base URL)

---

## 9. Design — Liquid Glass

Dictus fully embraces **iOS 26 Liquid Glass** — Apple's new design language — to deliver a native, premium feel without a price tag.

### 9.1 Design principles

- **Glassmorphism-native**: every panel uses the new Liquid Glass material APIs from iOS 26
- **Depth over flatness**: layered surfaces with realistic light refraction
- **Motion as feedback**: all state transitions expressed through fluid animations
- **Minimal chrome**: no heavy borders, no opaque backgrounds

### 9.2 Key UI components

#### Microphone button
- Large circular button (~72pt) with Liquid Glass material
- **Idle**: frosted glass, `mic.fill` SF Symbol, subtle inner glow
- **Recording**: glass tints red/orange, pulsing ring, real-time waveform
- **Transcribing**: spinning shimmer progress ring
- **Smart mode active**: subtle blue/purple tint to signal LLM is processing

#### Mode pill
- Floating Liquid Glass pill next to the mic button showing active mode name + icon
- Tap to open mode selector bottom sheet
- Animates smoothly when mode changes

#### Transcription preview zone
- Frosted glass card in the top bar of the keyboard
- Text appears word-by-word as transcription streams
- Editable inline — tapping puts cursor in the zone
- `[✓]` button confirms and keeps the inserted text

#### Keyboard background
- Full Liquid Glass backdrop
- Blurs the app content underneath
- Adapts to light/dark mode automatically

#### Onboarding
- Full-bleed gradient backgrounds with Liquid Glass panels
- Floating glass card per step with icon + text
- Smooth crossfade transitions

### 9.3 Color palette

| Token | Light | Dark | Usage |
|---|---|---|---|
| `primary` | `#1A3A5C` | `#E8F0FA` | Text, active states |
| `accent` | `#2E6DA4` | `#5B9BD5` | Buttons, highlights |
| `glass` | `systemUltraThinMaterial` | `systemUltraThinMaterial` | All surfaces |
| `recording` | `#FF4444` | `#FF6666` | Recording state |
| `smartMode` | `#5B5BD6` | `#7B7BFF` | LLM mode active |
| `success` | `#34C759` | `#30D158` | Successful insert |

### 9.4 Typography

- **SF Pro Rounded** for headings and UI labels
- **SF Pro Text** for body and transcription preview
- All sizes use Dynamic Type

### 9.5 State transition animations

| Trigger | Animation |
|---|---|
| Start recording | Mic scales 1.05×, ring expands, waveform fades in |
| Speaking | Waveform bars animate to real-time audio amplitude |
| Transcription starts | Waveform → spinning shimmer ring |
| Text appears | Words fade in with slight upward drift (staggered) |
| LLM processing | Mode pill pulses, mic ring shows blue shimmer |
| Insert confirmed | Text slides upward into field, preview card dissolves |
| Undo | Text retracts back into preview zone with reverse animation |
| Error | Button shakes horizontally, tints amber |

---

## 10. Roadmap

### V1 MVP — core experience (6–8 weeks)

| Sprint | Focus | Deliverables |
|---|---|---|
| S1 | Project setup | Xcode structure, 2 targets, App Group, WhisperKit via SPM, first model download |
| S2 | Main app | Onboarding (incl. keyboard layout selection), settings, model manager |
| S3 | Keyboard layout | Full AZERTY + QWERTY SwiftUI keyboard (no suggestions yet), extension shell |
| S4 | STT transcription | AVFoundation recording, WhisperKit in extension, filler word removal |
| S5 | Insertion + undo | Auto-insert via textDocumentProxy, undo gesture, preview zone, edit inline |
| S6 | Polish & testing | Error handling, edge cases, real device tests (iPhone 12/14/16 Pro), FR/EN validation |

### V1+ Advanced — keyboard & history (weeks 9–14)

| Sprint | Focus | Deliverables |
|---|---|---|
| S7 | Text prediction | UILexicon integration, suggestion bar, autocorrect, accented chars long-press |
| S8 | Smart modes | OpenAI GPT-4o integration, default modes (Email/SMS/Note/Slack), mode selector UI |
| S9 | Custom modes + history | Mode editor in settings, transcription history, API key management |

### V2 — power features (post V1+)

- Real-time streaming (word-by-word while recording)
- Additional LLM providers (Claude, Groq, Ollama, custom endpoint)
- Action Button shortcut (iPhone 15 Pro+)
- Dynamic Island integration during recording
- iCloud sync (preferences, custom modes, personal dictionary)
- iPad support

### V3 — future

- Android port (whisper.cpp + Flutter or Kotlin)
- iOS Shortcuts integration
- Apple Watch companion trigger

---

## 11. Distribution & Open Source

### App Store
- Free on the App Store under MIT licence
- Category: Utilities / Productivity
- No ads, no tracking, no data collection (STT mode)
- Privacy Nutrition Label: **Data Not Collected** (STT) / user-initiated API calls (smart modes)

> ⚠️ **App Store Review**: keyboard extensions requesting microphone + network access need clear review notes. Emphasize that STT is 100% on-device, and network calls only happen when the user explicitly configures an API key and selects a smart mode.

### GitHub
- Public repo under MIT licence (`github.com/[username]/dictus`)
- README with setup instructions, architecture overview, contribution guide
- `CONTRIBUTING.md` with development guide
- GitHub Actions: automated TestFlight builds on merge to `main`
- Issue templates for bugs and feature requests

---

## 12. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| App Store rejection (mic + network in extension) | Medium | Clear review notes, STT-only mode as default, video demo |
| Memory overrun in keyboard extension | High | Restrict to tiny/base/small, lazy loading, memory profiling with Instruments |
| AZERTY keyboard quality below Apple native | Medium | Extensive FR user testing, UILexicon for word list, iterate post-MVP |
| Text prediction complexity exceeds estimates | High | Scoped as V1+ not MVP — ship without suggestions first |
| OpenAI API latency in keyboard extension | Low | Show loading state in mode pill, set 10s timeout with fallback to raw STT |
| WhisperKit breaking API changes | Low | Pin version in Package.swift, test updates on separate branch |
| Name conflict or trademark issue | Very low | "Dictus" is a latin word, verify trademark search before App Store submission |

---

## 13. References

- [WhisperKit (Argmax)](https://github.com/argmaxinc/WhisperKit) — Swift framework for on-device Whisper
- [whisper.cpp (ggerganov)](https://github.com/ggerganov/whisper.cpp) — C++ Whisper, backup option
- [Handy](https://github.com/cjpais/Handy) — philosophical inspiration (desktop, MIT)
- [WhisperBoard](https://github.com/Saik0s/Whisperboard) — open source iOS reference implementation
- [Apple — Custom Keyboard Extensions](https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard)
- [Apple — UILexicon](https://developer.apple.com/documentation/uikit/uilexicon) — system word list for keyboards
- [OpenAI API](https://platform.openai.com/docs) — GPT-4o for smart modes
- [Apple HIG — iOS 26 Liquid Glass](https://developer.apple.com/design/human-interface-guidelines)

---

*Dictus PRD v1.1 — PIVI Solutions — 2026*
