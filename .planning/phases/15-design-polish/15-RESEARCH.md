# Phase 15: Design Polish - Research

**Researched:** 2026-03-13
**Domain:** SwiftUI UI polish, French localization, interaction feedback, bug diagnosis
**Confidence:** HIGH

## Summary

Phase 15 is a UI polish phase touching 10+ existing Swift files across DictusApp, DictusKeyboard, and DictusCore. The work breaks into four categories: (1) French accent audit across all UI strings, (2) model card redesign (tap-to-select, swipe-to-delete, blue-only gauge colors, active highlight), (3) recording overlay and mic button interaction improvements (hit area, haptics, dismiss animation), and (4) onboarding/settings UX fixes including a new success screen, two bugs (#25, #26), and one intermittent waveform bug.

All changes are constrained to existing SwiftUI patterns already established in the codebase. No new dependencies are needed. The codebase already has `HapticFeedback` with pre-allocated generators, `GlassPressStyle` for button interactions, `dictusGlass()` for card styling, and `withAnimation(.easeOut)` as the standard animation pattern.

**Primary recommendation:** Group work into 4 waves -- (1) French accent audit + gauge colors (quick text/color changes), (2) model card redesign (interaction model change), (3) overlay/mic polish + settings UX, (4) onboarding success screen + bug fixes. This ordering lets visual consistency land first before interaction changes.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Active model highlight**: Subtle blue background tint (dictusAccent at ~0.08-0.12 opacity) on the active model card -- no border, no "Actif" badge
- **Tap to select**: Tapping anywhere on a downloaded model card selects it as active. Remove "Choisir" button entirely
- **Tap to download**: Tapping anywhere on a non-downloaded model card starts the download. Remove download arrow icon button. User can cancel during download
- **Swipe to delete**: Remove visible trash button. Swipe left to reveal "Supprimer" action (like iOS Mail). Active model cannot be deleted
- **Gauge bar colors**: Change from blue/green to blue accent (#3D7EFF for Precision) + blue highlight (#6BA3FF for Vitesse). No more dictusSuccess green
- **Badges**: WK/PK engine badge and "Recommande" badge stay as-is
- **X button hit area**: Keep visual size (56x36 PillButton) but add invisible `.contentShape(Rectangle())` to ensure 44pt minimum tap area
- **Haptic feedback**: Claude's discretion on impact style (light vs medium) for both X (cancel) and checkmark (validate)
- **Dismiss animation**: Smooth easeOut animation applied on both cancel AND transcription complete. Claude's discretion on slide-down+fade vs fade-only
- **Mic button scope**: Both pill (keyboard toolbar) and circle (HomeView) -- AnimatedMicButton in both modes
- **Mic button approach**: Claude evaluates current opacity 0.5 + shimmer and adjusts if needed. Both contexts must be consistent
- **French accent scope**: UI strings only (Text(), Label(), .navigationTitle(), alert messages) -- not code comments
- **French accent method**: Systematic grep of all .swift files for French strings missing accents
- **Onboarding success screen (#27)**: Full-screen success overlay after transcription test, Apple Pay-style checkmark animation, "C'est pret !" title, "Commencer" button
- **Settings visual feedback (#28)**: Ensure Button inside List for native highlight, log export spinner
- **Bug #25**: Model downloaded during onboarding not recognized -- SharedPreferences sync issue
- **Bug #26**: Crash on return from keyboard settings -- race condition in scenePhase
- **Waveform bug**: Add diagnostic logging in RecordingOverlay before attempting fix

### Claude's Discretion
- Dismiss animation style (slide-down+fade vs fade-only)
- Haptic feedback style for overlay buttons (light vs medium impact)
- Mic button transcription opacity adjustment (current 0.5 may be sufficient)
- Exact blue background opacity for active model card (0.08-0.12 range)
- Success screen checkmark animation timing and spring parameters

### Deferred Ideas (OUT OF SCOPE)
- **#24: Sound feedback for recording start/stop** -- Full feature with SoundFeedbackService, settings page, WAV files. Separate phase (post-beta or v1.3)
- **Confetti/particle animation** for success screen -- considered but scale bounce is more appropriate for a utility app
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DSGN-01 | All French UI strings have correct accents | French accent audit identified 15+ strings across 7 files needing fixes |
| DSGN-02 | Active model has blue border highlight in model manager | Locked decision: blue background tint (not border), no badge. ModelCardView.swift already has `isActive` computed property |
| DSGN-03 | Model card layout improved (download button placement, badge/gauge alignment) | Redesign to tap-to-select/download, swipe-to-delete. Remove "Choisir" button, download arrow, trash button |
| DSGN-04 | Tap anywhere on downloaded model card to select it | Wrap card body in Button, use `modelManager.selectModel()` on tap for ready state |
| DSGN-05 | X close button on recording overlay has 44pt hit area + haptic feedback | PillButton is 56x36, needs `.contentShape(Rectangle())` for 44pt+ area. HapticFeedback already available |
| DSGN-06 | Recording overlay dismissal uses smooth easeOut animation | KeyboardRootView conditionally renders overlay based on `state.dictationStatus`. Animation on status change transition |
| DSGN-07 | Mic button shows reduced opacity during transcription processing | AnimatedMicButton already uses `opacity(0.5)` for transcribing fill color. Evaluate if sufficient |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 17+ | All UI views | Already the project's UI framework |
| DictusCore | local SPM | Shared design system, haptics, colors | Existing shared framework |

### Supporting
| Library | Purpose | When to Use |
|---------|---------|-------------|
| `HapticFeedback` (DictusCore) | Pre-allocated UIImpactFeedbackGenerator | Overlay button taps |
| `GlassPressStyle` (DictusCore) | Button press animation | All interactive glass elements |
| `dictusGlass()` modifier | Glass/material background | Card styling |
| `PersistentLog` (DictusCore) | Diagnostic logging | Waveform bug investigation |

### No New Dependencies
This phase requires zero new SPM packages. All work uses existing project infrastructure.

## Architecture Patterns

### Files That Need Modification

```
DictusApp/
├── Views/
│   ├── ModelCardView.swift       # DSGN-02/03/04: full redesign
│   ├── ModelManagerView.swift    # DSGN-03: add swipe-to-delete
│   ├── GaugeBarView.swift        # DSGN-03: color param changes at call sites
│   ├── SettingsView.swift        # DSGN-01: accent fixes, #28: button/spinner
│   ├── RecordingView.swift       # DSGN-01: accent fixes
│   └── HomeView.swift            # DSGN-01: accent fixes
├── Onboarding/
│   ├── ModelDownloadPage.swift   # DSGN-01: accent fixes, #25: sync bug
│   ├── KeyboardSetupPage.swift   # DSGN-01: accent fixes, #26: crash bug
│   ├── TestRecordingPage.swift   # #27: success screen redirect
│   └── OnboardingSuccessView.swift  # NEW: #27 success overlay
├── Models/
│   └── ModelManager.swift        # #25: verify persistState after onboarding download
DictusKeyboard/
├── Views/
│   └── RecordingOverlay.swift    # DSGN-05/06: hit area, haptics, dismiss anim, waveform bug
├── KeyboardRootView.swift        # DSGN-06: transition animation on overlay show/hide
DictusCore/
├── Sources/DictusCore/Design/
│   ├── AnimatedMicButton.swift   # DSGN-07: transcription opacity evaluation
│   └── DictusColors.swift        # Reference only (color constants)
```

### Pattern 1: Tap-to-Select Model Card
**What:** Wrap entire ModelCardView body in a Button that calls selectModel/downloadModel based on state
**When to use:** DSGN-03/04 model card redesign

```swift
// Current: separate "Choisir" / download arrow buttons in trailingContent
// New: entire card is tappable

var body: some View {
    Button {
        handleCardTap()
    } label: {
        VStack(alignment: .leading, spacing: 8) {
            // ... existing card content minus buttons ...
        }
        .padding(16)
        .background(
            // Active model highlight
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? Color.dictusAccent.opacity(0.10) : Color.clear)
        )
        .dictusGlass()
    }
    .buttonStyle(GlassPressStyle())
    .disabled(state == .downloading || state == .prewarming)
}

private func handleCardTap() {
    switch state {
    case .ready:
        if !isActive {
            modelManager.selectModel(model.identifier)
        }
    case .notDownloaded:
        Task {
            try await modelManager.downloadModel(model.identifier)
        }
    case .error:
        modelManager.cleanupFailedModel(model.identifier)
    default:
        break
    }
}
```

### Pattern 2: Swipe-to-Delete (iOS Standard)
**What:** Use `.swipeActions` modifier on ForEach items in ModelManagerView
**When to use:** DSGN-03 replacing visible trash button

```swift
// In ModelManagerView, wrap each card in swipeActions
ForEach(models) { model in
    ModelCardView(model: model, modelManager: modelManager, ...)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if modelManager.downloadedModels.contains(model.identifier)
                && modelManager.activeModel != model.identifier
                && modelManager.downloadedModels.count > 1 {
                Button("Supprimer", role: .destructive) {
                    modelToDelete = model
                    showDeleteAlert = true
                }
            }
        }
}
```

**Important:** `.swipeActions` requires the view to be inside a `List` or `ForEach` inside a `List`. Currently ModelManagerView uses `ScrollView > VStack > ForEach`. Two approaches:
1. Keep ScrollView layout, implement custom swipe gesture (more work, matches current design)
2. Switch to `List` with custom row styling (native swipe, but requires adapting glass card styling)

Recommendation: Use a custom swipe gesture with `DragGesture` on each card to reveal delete, since converting to List would change the entire visual style. Alternatively, use a `.contextMenu` for delete as a simpler fallback.

### Pattern 3: Overlay Dismiss Animation
**What:** Add transition animation when RecordingOverlay appears/disappears in KeyboardRootView
**When to use:** DSGN-06

```swift
// In KeyboardRootView body, add transition + animation
if showsOverlay {
    RecordingOverlay(...)
        .frame(height: totalContentHeight)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
} else {
    // toolbar + keyboard
}
// Add animation modifier
.animation(.easeOut(duration: 0.25), value: showsOverlay)
```

**Key consideration:** The `if/else` conditional rendering in KeyboardRootView is driven by `state.dictationStatus`. The transition animation needs to wrap the conditional in a way that SwiftUI can interpolate. Using `.animation()` on the VStack with value tracking `dictationStatus` changes should work.

### Pattern 4: Success Screen (Onboarding #27)
**What:** New OnboardingSuccessView with scale-bounce checkmark, shown after TestRecordingPage transcription
**When to use:** #27 onboarding completion

```swift
struct OnboardingSuccessView: View {
    let onComplete: () -> Void
    @State private var checkmarkScale: CGFloat = 0
    @State private var showText = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated checkmark circle
            ZStack {
                Circle()
                    .fill(Color.dictusSuccess)
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
            }
            .scaleEffect(checkmarkScale)

            if showText {
                VStack(spacing: 12) {
                    Text("C'est pret !")
                        .font(.dictusHeading)
                    Text("Dictus est configure et pret a l'emploi")
                        .font(.dictusBody)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            Spacer()

            if showText {
                Button("Commencer") { onComplete() }
                    // ... standard button styling ...
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                checkmarkScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                showText = true
            }
        }
    }
}
```

**Note:** The success text strings also need correct French accents: "C'est pr**e**t !" and "configur**e** et pr**e**t **a** l'emploi" -- these should be "C'est pr**e with accent**t !" etc. The CONTEXT.md specifies the exact text.

### Anti-Patterns to Avoid
- **Hardcoding haptic styles per-call:** Use HapticFeedback enum methods, not raw UIImpactFeedbackGenerator calls
- **DispatchQueue.main.asyncAfter for animations:** Use withAnimation(.easeOut) (established Phase 12 pattern)
- **Modifying state.dictationStatus directly for animation:** Track overlay visibility with a separate @State property if needed

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Haptic feedback | Raw UIImpactFeedbackGenerator | `HapticFeedback.recordingStopped()` / `.keyTapped()` | Pre-allocated generators, respects user toggle |
| Button press animation | Custom gesture + scale | `GlassPressStyle()` | Consistent feel across all glass surfaces |
| Glass card background | Custom material + blur | `.dictusGlass()` modifier | Handles iOS 26 Liquid Glass + iOS 17 fallback |
| Swipe actions in List | Custom DragGesture | `.swipeActions()` on List items | Native iOS behavior, handles edge cases |

## Common Pitfalls

### Pitfall 1: SwipeActions Requires List Context
**What goes wrong:** `.swipeActions` modifier is silently ignored on views not inside a `List`
**Why it happens:** Current ModelManagerView uses `ScrollView > VStack > ForEach`, not `List`
**How to avoid:** Either convert to List (changes visual style) or implement custom swipe with DragGesture. If using List, apply `.listRowBackground(Color.clear)` and `.listRowSeparator(.hidden)` to preserve glass card look.
**Warning signs:** Swipe gesture does nothing on model cards

### Pitfall 2: Transition Animation on Conditional Views
**What goes wrong:** SwiftUI won't animate `if/else` view swaps without explicit `.transition()` and `.animation()`
**Why it happens:** Conditional rendering replaces views entirely. Without transitions, changes are instant.
**How to avoid:** Add `.transition(.opacity)` to both branches, `.animation(.easeOut, value: statusBool)` on parent
**Warning signs:** Overlay appears/disappears abruptly

### Pitfall 3: ContentShape for Hit Area vs Visual Size
**What goes wrong:** `.contentShape(Rectangle())` must be applied OUTSIDE the button label's visual frame to expand hit area
**Why it happens:** If applied inside the label, it clips the content shape to the label bounds
**How to avoid:** Apply `.contentShape(Rectangle().size(width: 56, height: 44))` or wrap PillButton in a larger invisible frame
**Warning signs:** Tap area still feels small despite adding contentShape

### Pitfall 4: Onboarding ModelManager Instance Mismatch (#25)
**What goes wrong:** ModelDownloadPage creates its own `@StateObject private var modelManager = ModelManager()`. This is a SEPARATE instance from the one used in ModelManagerView.
**Why it happens:** Each page instantiates its own ModelManager. Both call `persistState()` to App Group, but the ModelManagerView instance re-reads from App Group only in `init()`.
**How to avoid:** Verify that `ModelManager.loadState()` is called in ModelManagerView's `.onAppear` to pick up state written by onboarding's ModelManager instance. Add `modelManager.loadState()` call.
**Warning signs:** Model shows as downloaded in onboarding but not in model manager

### Pitfall 5: scenePhase Race During Onboarding (#26)
**What goes wrong:** Returning from iOS Settings triggers `.active` scenePhase change. If `checkKeyboardInstalled()` runs while the view is still transitioning, it may cause a state mutation crash.
**Why it happens:** iOS fires scenePhase changes asynchronously. `onChange(of: scenePhase)` can fire during view transitions.
**How to avoid:** Guard keyboard detection with a small delay or use `.task` to debounce. Add crash logging around the detection code.
**Warning signs:** Intermittent crash ~1 in 2-3 returns from Settings

### Pitfall 6: Keyboard Extension Memory with BrandWaveform
**What goes wrong:** BrandWaveform uses TimelineView(.animation) which runs at 60fps. If the view is retained but not visible, it wastes CPU/memory.
**Why it happens:** SwiftUI may keep TimelineView ticking even when RecordingOverlay is conditionally removed
**How to avoid:** The current `if/else` conditional rendering in KeyboardRootView fully removes RecordingOverlay from hierarchy. Verify this behavior is maintained when adding transition animations.
**Warning signs:** Elevated CPU when keyboard is idle

## Code Examples

### French Accent Fixes (Complete Audit)

Verified strings needing accent fixes (grep results from codebase):

| File | Current | Correct |
|------|---------|---------|
| ModelCardView.swift:57 | `"Recommande"` | `"Recommandé"` |
| ModelCardView.swift:76 | `"Precision"` | `"Précision"` |
| ModelCardView.swift:195 | `"Reessayer"` | `"Réessayer"` |
| GaugeBarView.swift:49 | `"Precision"` (preview) | `"Précision"` |
| SettingsView.swift:42 | `"Francais"` | `"Français"` |
| SettingsView.swift:67 | `Section("A propos")` | `Section("À propos")` |
| SettingsView.swift:108 | `"Reglages"` | `"Réglages"` |
| RecordingOverlay.swift:93 | `"Demarrage..."` | `"Démarrage..."` |
| KeyboardSetupPage.swift:50 | `"Ouvrir les Reglages"` | `"Ouvrir les Réglages"` |
| KeyboardSetupPage.swift:57 | `"sera detecte automatiquement"` | `"sera détecté automatiquement"` |
| KeyboardSetupPage.swift:65 | `"Clavier detecte"` | `"Clavier détecté"` |
| KeyboardSetupPage.swift:129 | `"Reglages > Dictus"` | `"Réglages > Dictus"` |
| ModelDownloadPage.swift:44 | `"Modele vocal"` | `"Modèle vocal"` |
| ModelDownloadPage.swift:50 | `"modele vocal. Le telechargement"` | `"modèle vocal. Le téléchargement"` |
| ModelDownloadPage.swift:118 | `"Installer le modele"` | `"Installer le modèle"` |
| ModelDownloadPage.swift:152 | `"Modele vocal"` (fallback) | `"Modèle vocal"` |
| ModelDownloadPage.swift:160 | `"Precis et equilibre"` (fallback) | `"Précis et équilibré"` |
| ModelDownloadPage.swift:166 | `"Recommande pour votre iPhone"` | `"Recommandé pour votre iPhone"` |
| RecordingView.swift:262 | `"Arreter l'enregistrement"` | `"Arrêter l'enregistrement"` |
| RecordingView.swift:307 | `"echoue. Verifiez que le modele est telecharge"` | `"échoué. Vérifiez que le modèle est téléchargé"` |
| HomeView.swift:181 | `"Nouvelle dictee"` | `"Nouvelle dictée"` |
| MainTabView.swift:69 | `"Reglages"` | `"Réglages"` |

### Gauge Bar Color Change
```swift
// ModelCardView.swift, Row 3 -- change Vitesse color from green to blue highlight
GaugeBarView(
    value: model.speedScore,
    label: "Vitesse",
    color: .dictusAccentHighlight  // was .dictusSuccess
)
```

### PillButton Hit Area Expansion
```swift
// RecordingOverlay.swift PillButton -- add contentShape for 44pt minimum
Button(action: action) {
    Image(systemName: icon)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(color)
        .frame(width: 56, height: 44) // increase height from 36 to 44
        .contentShape(Rectangle()) // ensure full area is tappable
        .dictusGlass(in: Capsule())
}
.buttonStyle(GlassPressStyle())
```

### Haptic Feedback for Overlay Buttons
```swift
// Add haptic to PillButton action
PillButton(icon: "xmark", color: secondaryForeground) {
    HapticFeedback.recordingStopped()  // light impact for cancel
    onCancel()
}

PillButton(icon: "checkmark", color: .dictusSuccess) {
    HapticFeedback.recordingStopped()  // light impact for validate
    onStop()
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| "Choisir" button + trash icon | Tap-to-select + swipe-to-delete | Phase 15 | Cleaner card layout, fewer UI elements |
| Green gauge for speed | Blue accent highlight for speed | Phase 15 | Consistent brand palette |
| "Actif" badge on model card | Blue background tint | Phase 15 | More subtle, more visual |
| Inline "Terminer" button | Full success overlay | Phase 15 | Professional onboarding completion |

## Open Questions

1. **SwipeActions in ScrollView**
   - What we know: `.swipeActions` only works in `List` context, not `ScrollView > VStack`
   - What's unclear: Whether converting ModelManagerView to use `List` will break the glass card aesthetic
   - Recommendation: Try `.swipeActions` with `List` + `.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)` + `.listRowInsets(EdgeInsets())`. If visual quality suffers, fall back to custom `DragGesture`-based swipe or `.contextMenu`.

2. **Waveform Disappearance Bug Root Cause**
   - What we know: Intermittent, hard to reproduce. RecordingOverlay conditionally renders BrandWaveform.
   - What's unclear: Whether the issue is in energy data delivery (waveformEnergy empty), BrandWaveform rendering (displayLevels stuck at zero), or SwiftUI view lifecycle (TimelineView not updating)
   - Recommendation: Add PersistentLog calls at: (a) RecordingOverlay body evaluation with waveformEnergy.count, (b) BrandWaveform.updateDisplayLevels() entry, (c) KeyboardState when waveformEnergy is updated from App Group. Diagnose first, fix second.

3. **Crash Bug #26 Specifics**
   - What we know: Intermittent crash returning from iOS Settings during onboarding
   - What's unclear: Exact crash log / stack trace not available in research
   - Recommendation: Add PersistentLog around KeyboardSetupPage.checkKeyboardInstalled() and scenePhase onChange. Wrap UITextInputMode.activeInputModes in a guard. Consider debouncing with Task + try await Task.sleep.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing / XCTest via SPM |
| Config file | `DictusCore/Package.swift` |
| Quick run command | `cd DictusCore && swift test --filter DictusCoreTests` |
| Full suite command | `cd DictusCore && swift test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DSGN-01 | French accent strings correct | manual-only | Visual inspection in Simulator | N/A |
| DSGN-02 | Active model blue highlight | manual-only | Visual inspection | N/A |
| DSGN-03 | Model card layout (tap/swipe) | manual-only | Interaction testing in Simulator | N/A |
| DSGN-04 | Tap-to-select model card | manual-only | Interaction testing | N/A |
| DSGN-05 | X button 44pt hit area + haptic | manual-only | Test on device (haptics require hardware) | N/A |
| DSGN-06 | Overlay dismiss animation | manual-only | Visual inspection | N/A |
| DSGN-07 | Mic button transcription opacity | manual-only | Visual inspection | N/A |

**Justification for manual-only:** All DSGN requirements are visual/interaction polish. They cannot be meaningfully validated via unit tests. They require visual inspection in Simulator (iPhone 17 Pro) and haptic testing on physical device.

### Sampling Rate
- **Per task commit:** `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test --filter DictusCoreTests` (ensure no regressions in shared framework)
- **Per wave merge:** Full `swift test` + Xcode build for both DictusApp and DictusKeyboard targets
- **Phase gate:** All targets build without errors + visual verification on Simulator

### Wave 0 Gaps
None -- existing test infrastructure covers all testable components. DSGN requirements are visual/interaction and validated manually.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis: All files read and grep-audited for French strings, current implementations verified
- ModelCardView.swift, RecordingOverlay.swift, AnimatedMicButton.swift, GlassModifier.swift, HapticFeedback.swift -- complete reads
- ModelManager.swift, ModelDownloadPage.swift, KeyboardSetupPage.swift -- bug diagnosis context

### Secondary (MEDIUM confidence)
- SwiftUI `.swipeActions` behavior in ScrollView vs List context -- based on SwiftUI framework knowledge (iOS 17)
- `.contentShape()` for hit area expansion -- established SwiftUI pattern

### Tertiary (LOW confidence)
- Bug #26 crash root cause -- speculative without crash logs, needs diagnosis with logging

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all existing project patterns
- Architecture: HIGH -- code thoroughly reviewed, patterns documented with file/line references
- Pitfalls: MEDIUM -- bugs #25/#26 need runtime diagnosis, swipeActions in non-List context needs testing
- French accent audit: HIGH -- complete grep performed, all instances catalogued

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (stable, no external dependency changes)
