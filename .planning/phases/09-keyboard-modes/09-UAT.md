---
status: diagnosed
phase: 09-keyboard-modes
source: 09-01-SUMMARY.md, 09-02-SUMMARY.md, 09-03-SUMMARY.md
started: 2026-03-09T22:30:00Z
updated: 2026-03-10T08:40:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

## Tests

### 1. Mode Picker in Settings
expected: In DictusApp Settings, the "Clavier" section shows a segmented control with three options: Micro, Emoji+, Complet. Tapping each option selects it and the selection persists.
result: pass

### 2. Conditional Toggles per Mode
expected: When "Complet" is selected, AZERTY/QWERTY layout toggle and autocorrect toggle are visible. When "Micro" is selected, haptics toggle is hidden. When "Emoji+" is selected, layout toggles are hidden.
result: pass

### 3. Onboarding Mode Selection Step
expected: Onboarding now has 6 steps. Step 3 shows a mode selection page with the same Micro/Emoji+/Complet picker and miniature previews. The "Continuer" button is disabled until a mode is selected.
result: pass

### 4. Micro Mode Keyboard
expected: After selecting Micro mode in Settings, open the keyboard in any app. The keyboard shows a large mic pill button (120pt) with "Dicter" label and a globe button in the bottom-left. No letter keys, no emoji, no toolbar — just the mic and globe.
result: issue
reported: "Le micro ne marche pas tout le temps, impossible de le faire fonctionner même après redémarrage de l'app. Background color mismatch — le gris du clavier ne matche pas le fond blanc/clair en bas. Le globe fait doublon avec celui du système. Il manque des touches utiles en bas : emoji, espace, retour ligne, supprimer."
severity: major

### 5. Emoji+ Mode Keyboard
expected: After selecting Emoji+ mode, the keyboard shows the emoji picker grid (4 rows, continuous scroll) with a simplified toolbar above containing a globe button and a mic pill. No letter keys visible.
result: issue
reported: "Largeur de la grille emoji dépasse du cadre du clavier (coupée à gauche et droite). Toolbar/category bar coupée en haut. Globe en haut à gauche devrait être remplacé par le module réglages comme sur le clavier Complet (globe système déjà présent en bas). Devrait reprendre exactement le layout du emoji picker du mode Complet qui fonctionne bien."
severity: major

### 6. Full Mode Keyboard (Unchanged)
expected: After selecting Complet mode, the keyboard shows the standard AZERTY/QWERTY layout with all keys, toolbar, mic button, and emoji toggle — the same behavior as before Phase 9.
result: issue
reported: "Le mode picker ne persiste pas toujours le changement — impossible de passer en mode Complet depuis un autre mode sans rebuild. Le mode Complet lui-même fonctionne correctement une fois actif (retours optiques, corrections auto OK). Besoin de logs sur le choix du clavier pour diagnostiquer la sync App Group."
severity: major

### 7. Recording Overlay Across Modes
expected: Start a dictation recording from any of the three modes. The recording overlay (waveform, timer, controls) appears correctly on top of the current mode's layout without layout jumps or visual glitches.
result: issue
reported: "Impossible de tester — la communication App Group entre l'app et le clavier est cassée. Le mode ne switch pas et la dictation ne se lance pas depuis le clavier emoji. Probablement le même bug de sync/persistance App Group que le test 6."
severity: blocker

## Summary

total: 7
passed: 3
issues: 4
pending: 0
skipped: 0

## Gaps

- truth: "Micro mode keyboard shows large mic pill that reliably triggers dictation, with matching background color and appropriate utility keys"
  status: failed
  reason: "User reported: Le micro ne marche pas tout le temps, impossible de le faire fonctionner même après redémarrage de l'app. Background color mismatch — le gris du clavier ne matche pas le fond blanc/clair en bas. Le globe fait doublon avec celui du système. Il manque des touches utiles en bas : emoji, espace, retour ligne, supprimer."
  severity: major
  test: 4
  root_cause: "4 issues: (1) No background modifier — clear bg shows iOS keyboard chrome two-tone effect. (2) Manual globe button redundant with system globe. (3) ZStack layout has no bottom row structure for utility keys. (4) Mic .disabled() doesn't include .requested state — double-tap during 500ms Darwin window."
  artifacts:
    - path: "DictusKeyboard/Views/MicroModeView.swift"
      issue: "All 4 issues — needs background, remove globe, restructure ZStack→VStack with bottom utility row, add .requested to disabled states"
  missing:
    - "Add explicit background matching system keyboard chrome"
    - "Remove globe button (system provides it)"
    - "Restructure to VStack with bottom HStack: emoji, space, return, delete"
    - "Add .requested to mic button disabled states"
  debug_session: ".planning/debug/micro-mode-layout.md"

- truth: "Emoji+ mode keyboard shows emoji picker grid properly fitted within keyboard bounds with correct toolbar"
  status: failed
  reason: "User reported: Largeur de la grille emoji dépasse du cadre du clavier (coupée à gauche et droite). Toolbar/category bar coupée en haut. Globe en haut à gauche devrait être remplacé par le module réglages comme sur le clavier Complet (globe système déjà présent en bas). Devrait reprendre exactement le layout du emoji picker du mode Complet qui fonctionne bien."
  severity: major
  test: 5
  root_cause: "3 issues: (1) VStack wrapping EmojiPickerView has no .clipped() — ScrollView bleeds past edges. (2) Vertical space starvation — 48pt toolbar eats into picker height, unlike full mode which hides toolbar and expands height by 56pt for emoji. (3) Globe should be gear icon linking to dictus:// like ToolbarView."
  artifacts:
    - path: "DictusKeyboard/Views/EmojiMicroModeView.swift"
      issue: "Missing .clipped(), toolbar steals vertical space, globe instead of gear"
  missing:
    - "Add .clipped() to VStack or EmojiPickerView container"
    - "Fix vertical space: remove separate toolbar and integrate mic+gear into EmojiCategoryBar, or increase totalHeight by 48pt"
    - "Replace globe with gear icon (Link to dictus://) matching ToolbarView pattern"
    - "Wire onDismiss to advanceToNextInputMode() so ABC button becomes keyboard switcher"
  debug_session: ".planning/debug/emoji-micro-mode-layout.md"

- truth: "Mode picker in Settings reliably switches keyboard mode and the keyboard extension picks up the new mode without rebuild"
  status: failed
  reason: "User reported: Le mode picker ne persiste pas toujours le changement — impossible de passer en mode Complet depuis un autre mode sans rebuild. Besoin de logs sur le choix du clavier pour diagnostiquer la sync App Group."
  severity: major
  test: 6
  root_cause: "KeyboardRootView stores mode in @State and reads KeyboardMode.active only in .onAppear. In keyboard extensions, .onAppear fires once on first insertion — subsequent keyboard opens reuse the same view. viewWillAppear in KeyboardViewController IS called every show but doesn't trigger mode refresh."
  artifacts:
    - path: "DictusKeyboard/KeyboardRootView.swift"
      issue: "@State currentMode only set in .onAppear (line 25, 139) — stale after first show"
    - path: "DictusKeyboard/KeyboardViewController.swift"
      issue: "viewWillAppear exists (line 78) but doesn't notify SwiftUI to refresh mode"
  missing:
    - "Post notification from viewWillAppear (e.g. .dictusKeyboardWillAppear)"
    - "Add .onReceive in KeyboardRootView to re-read KeyboardMode.active on that notification"
    - "Add os_log for mode changes to aid debugging"
  debug_session: ".planning/debug/appgroup-mode-sync.md"

- truth: "Recording overlay works across all three keyboard modes without layout issues"
  status: failed
  reason: "User reported: Impossible de tester — la communication App Group entre l'app et le clavier est cassée. Le mode ne switch pas et la dictation ne se lance pas depuis le clavier emoji. Probablement le même bug de sync/persistance App Group que le test 6."
  severity: blocker
  test: 7
  root_cause: "Blocked by same App Group sync bug as test 6. Once mode refresh is fixed (viewWillAppear notification), this should be re-testable. The RecordingOverlay itself is correctly placed above the mode switch in KeyboardRootView."
  artifacts:
    - path: "DictusKeyboard/KeyboardRootView.swift"
      issue: "Same as test 6 — mode not refreshing blocks dictation from non-default mode"
  missing:
    - "Fix test 6 first, then re-verify overlay across modes"
  debug_session: ".planning/debug/appgroup-mode-sync.md"
