---
status: testing
phase: 15-design-polish
source: 15-01-SUMMARY.md, 15-02-SUMMARY.md, 15-03-SUMMARY.md, 15-04-SUMMARY.md, 15-05-SUMMARY.md
started: 2026-03-13T11:00:00Z
updated: 2026-03-13T14:15:00Z
---

## Current Test

[retest complete]

## Tests

### 1. French Accents — Settings & Home
expected: Open the app. Go to Settings (Réglages tab). All labels show correct French accents: "Réglages", "À propos", "Français". Go to Home tab: "Nouvelle dictée", "Modèle actif", "Télécharger", "Dernière transcription". Check Modèles tab label has accent.
result: pass

### 2. French Accents — Onboarding
expected: Reset onboarding (or fresh install). Go through onboarding flow. On MicPermissionPage: "Réglages" and "autorisé" have accents. On ModelDownloadPage: "modèle", "téléchargement", "Précis", "équilibré", "Recommandé" have accents. On KeyboardSetupPage: "Réglages", "détecté" have accents.
result: pass

### 3. Gauge Bar Blue Palette
expected: Open the Model Manager. Look at any model card's gauge bars. Both "Vitesse" and "Précision" bars should use blue tones only (no green anywhere). Preview colors are consistent blue shades.
result: pass

### 4. Log Export Spinner
expected: Go to Settings. Tap the log export option. While logs are being gathered, a spinning ProgressView indicator should appear. It disappears once the share sheet is ready.
result: pass

### 5. Model Card Tap Interaction
expected: Go to Model Manager. Tap an already-downloaded model card → it becomes the active model. Tap a not-yet-downloaded model card → download starts. No separate "Select" or "Download" buttons visible — the entire card is the tap target.
result: issue
reported: "Globalement très bien amélioré. 2 retours : 1) Remettre le fond teinté bleu pour le modèle actif EN PLUS de la bordure bleu foncé (les deux ensemble). 2) Enlever l'animation de chargement au switch de modèle — c'est instantané maintenant et le spinner agrandit brièvement la carte, ce qui fait un bug visuel."
severity: minor

### 6. Active Model Blue Highlight
expected: In Model Manager, the currently active model card has a subtle blue background tint AND dark blue border distinguishing it from other cards.
result: issue
reported: "Même retour que test 5 : remettre le fond teinté bleu + garder la bordure. Enlever le spinner de chargement au switch (instantané, bug visuel d'agrandissement de carte)."
severity: minor

### 7. Swipe-to-Delete Model
expected: In Model Manager, swipe left on a downloaded model that is NOT the active model. A red delete option appears. Tap it → confirmation alert. Confirm → model is deleted. The active model card should NOT be swipeable for delete.
result: issue
reported: "Couleur rouge OK maintenant. Mais le bouton Supprimer ne fait pas la même hauteur que la carte — devrait matcher la hauteur de la carte pour un rendu plus propre."
severity: cosmetic

### 8. Recording Overlay Buttons & Haptics
expected: Start a dictation from the keyboard. The recording overlay appears. Tap the cancel or stop button — the tap target feels generous (easy to hit), and you feel a light haptic vibration on tap.
result: pass

### 9. Recording Overlay Transition Animation
expected: Start a dictation. The recording overlay should appear with a smooth fade+slide animation (not instant pop). When stopping/cancelling, it should disappear with a matching smooth animation.
result: issue
reported: "La transition fade est OK. Problème principal : décalage vertical de la waveform entre l'état recording (avec texte 'Listening' en dessous) et l'état transcription (sans texte). Le texte 'Listening' pousse la waveform plus bas, et quand on passe en transcription la waveform saute vers le haut. La waveform doit rester sur la même ligne verticale quel que soit l'état. Aussi : 'Listening' devrait être en français ('En écoute...' ou similaire)."
severity: major

### 10. Onboarding Success Screen
expected: During onboarding, complete the test recording step. After transcription succeeds, a full-screen success overlay appears with an animated checkmark (spring bounce effect) and a "Commencer" button. Tapping it completes onboarding.
result: pass
note: "OK mais le success screen pourrait arriver un peu plus vite (réduire le délai)."

### 11. Keyboard Detection After Settings Return
expected: During onboarding on the keyboard setup step, go to iOS Settings to enable the Dictus keyboard. Return to the app. The app should detect the keyboard without crashing or freezing. No race condition issues.
result: pass
note: "Crash encore intermittent mais pas bloquant. Logging ajouté — à surveiller en bêta. Pas d'issue GitHub existante, à créer."

### 12. Active Model Name on Home Screen
expected: Home screen shows correct model name without engine prefix. Parakeet models show "Parakeet v3", WhisperKit models show "Small", "Medium", etc.
result: pass

### 13. Settings Tap Feedback
expected: When tapping items in Settings, the row flashes gray briefly (like native iOS Settings) to confirm the tap was registered.
result: issue
reported: "Le flash gris ne couvre que la hauteur du texte, pas toute la surface du row/bouton. Devrait couvrir toute la zone comme iOS natif. En plus, ne fonctionne que sur le lien GitHub — les autres boutons (Licence, Diagnostic, Debug Logs) n'ont aucun feedback visuel."
severity: major

### 14. Model State Sync After Onboarding
expected: After completing onboarding, the model downloaded during onboarding appears as active in Model Manager — no download icon, properly recognized.
result: pass

### 15. Engine Descriptions Fixed Footer
expected: The WhisperKit and Parakeet description paragraphs are always at the bottom of the Models page as a fixed footer, not attached to any model card or section.
result: pass

### 16. Section Headers Scroll With Content
expected: The "Téléchargés" and "Disponibles" section headers scroll naturally with the rest of the content — no sticky/pinned behavior that overlaps cards.
result: pass

## Summary

total: 16
passed: 11
issues: 5
pending: 0
skipped: 0

## Gaps

- truth: "Active model card has both blue background tint AND dark blue border"
  status: failed
  reason: "User reported: Remettre le fond teinté bleu en plus de la bordure. Enlever le spinner de chargement au switch — instantané, spinner cause bug visuel d'agrandissement de carte."
  severity: minor
  test: 5
  artifacts: []
  missing: []

- truth: "Active model card has both blue background tint AND dark blue border"
  status: failed
  reason: "User reported: Même retour — fond teinté + bordure ensemble. Enlever spinner switch modèle."
  severity: minor
  test: 6
  artifacts: []
  missing: []

- truth: "Swipe delete button matches card height"
  status: failed
  reason: "User reported: Bouton Supprimer ne fait pas la même hauteur que la carte"
  severity: cosmetic
  test: 7
  artifacts: []
  missing: []

- truth: "Waveform stays at same vertical position across recording/transcription states"
  status: failed
  reason: "User reported: Décalage vertical de la waveform entre recording (texte Listening pousse vers le bas) et transcription (pas de texte, waveform remonte). Aussi Listening doit être en français."
  severity: major
  test: 9
  artifacts: []
  missing: []

- truth: "Settings tap feedback covers full row area on all interactive items"
  status: failed
  reason: "User reported: Flash gris uniquement sur la hauteur du texte, pas toute la surface. Ne fonctionne que sur le lien GitHub, pas sur Licence/Diagnostic/Debug Logs."
  severity: major
  test: 13
  artifacts: []
  missing: []
