---
status: complete
phase: 15-design-polish
source: 15-01-SUMMARY.md, 15-02-SUMMARY.md, 15-03-SUMMARY.md, 15-04-SUMMARY.md, 15-05-SUMMARY.md
started: 2026-03-13T11:00:00Z
updated: 2026-03-13T11:10:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

[testing complete]

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
reported: "Globalement ça marche mais plusieurs problèmes : 1) Barre de téléchargement trop petite en bas à droite, devrait prendre toute la largeur de la carte et masquer les jauges pendant download/optimisation (comme app Handy). 2) Quand on lance un download, la carte devrait passer de la section Disponible à la section Téléchargés en état downloading. 3) Zone de tap pas assez sensible, faut cliquer au centre de la carte, pas fluide, plusieurs clics nécessaires parfois. 4) Manque animation de press iOS standard (scale bounce : grossit légèrement puis revient). 5) Modèle actif : préfère une bordure bleu foncé autour de la carte plutôt que le fond teinté."
severity: major

### 6. Active Model Blue Highlight
expected: In Model Manager, the currently active model card has a subtle blue background tint distinguishing it from other cards. Other cards have no tint.
result: issue
reported: "Même remarque que test 5 : préfère bordure bleu foncé autour de la carte au lieu du fond teinté. Aussi enlever le check vert en bas à droite de la carte active. Et ajouter un feedback de chargement quand on switch de modèle (animation préparation en cours) pour montrer que le clic est pris en compte, car parfois le switch prend 1-2 secondes."
severity: major

### 7. Swipe-to-Delete Model
expected: In Model Manager, swipe left on a downloaded model that is NOT the active model. A red delete option appears. Tap it → confirmation alert. Confirm → model is deleted. The active model card should NOT be swipeable for delete.
result: issue
reported: "Le swipe fonctionne bien et la suppression aussi, mais le bouton Supprimer est bleu au lieu de rouge."
severity: minor

### 8. Recording Overlay Buttons & Haptics
expected: Start a dictation from the keyboard. The recording overlay appears. Tap the cancel or stop button — the tap target feels generous (easy to hit), and you feel a light haptic vibration on tap.
result: [pending]

### 9. Recording Overlay Transition Animation
expected: Start a dictation. The recording overlay should appear with a smooth fade+slide animation (not instant pop). When stopping/cancelling, it should disappear with a matching smooth animation.
result: issue
reported: "L'apparition en fade in est bien. Mais à la disparition, l'overlay descend vers le bas (slide down) — pas fan. Préfère un simple fade out sans mouvement."
severity: minor

### 10. Onboarding Success Screen
expected: During onboarding, complete the test recording step. After transcription succeeds, a full-screen success overlay appears with an animated checkmark (spring bounce effect) and a "Commencer" button. Tapping it completes onboarding.
result: issue
reported: "Le success screen fonctionne bien. Mais juste avant, il y a un gros bouton vert Terminé en plein milieu de l'écran qui est moche. Voudrait le supprimer : après transcription, afficher le résultat brièvement puis enchaîner automatiquement sur le success screen. Si la transcription échoue, proposer de réessayer."
severity: minor

### 11. Keyboard Detection After Settings Return
expected: During onboarding on the keyboard setup step, go to iOS Settings to enable the Dictus keyboard. Return to the app. The app should detect the keyboard without crashing or freezing. No race condition issues.
result: issue
reported: "Crash intermittent au retour de iOS Settings après avoir activé le clavier. L'app se relance (visible dans logs : appDidEnterBackground puis appLaunched). Pas de stack trace dans les logs actuels. Demande d'ajouter du logging autour de l'onboarding keyboard detection pour diagnostiquer en bêta."
severity: major

## Summary

total: 11
passed: 4
issues: 6
pending: 0
skipped: 0

## Gaps

- truth: "Model card tap interaction: full card tappable, download starts on tap, no separate buttons"
  status: failed
  reason: "User reported: 1) Download progress bar too small, should be full-width hiding gauges during download/optimization (like Handy app). 2) Card should move from Available to Downloaded section when download starts. 3) Tap area not responsive enough, must tap center, multiple taps needed. 4) Missing iOS standard press animation (scale bounce). 5) Active model should have dark blue border instead of background tint."
  severity: major
  test: 5
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Swipe-to-delete button appears in red (destructive action)"
  status: failed
  reason: "User reported: Le bouton Supprimer en swipe est bleu au lieu de rouge"
  severity: minor
  test: 7
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Recording overlay disappears with smooth matching animation"
  status: failed
  reason: "User reported: Fade in à l'apparition est bien, mais la disparition slide vers le bas — préfère un simple fade out sans mouvement"
  severity: minor
  test: 9
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Onboarding success screen flows smoothly after test recording"
  status: failed
  reason: "User reported: Le success screen marche mais le gros bouton vert Terminé juste avant est moche. Supprimer ce bouton, afficher le résultat de transcription brièvement puis enchaîner auto sur success screen. Si échec transcription, proposer réessayer."
  severity: minor
  test: 10
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Keyboard detection after iOS Settings return works without crash"
  status: failed
  reason: "User reported: Crash intermittent au retour de Settings après activation du clavier. App se relance. Pas de stack trace disponible. Besoin de logging supplémentaire autour de l'onboarding keyboard detection pour diagnostiquer."
  severity: major
  test: 11
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""

- truth: "Active model card visually distinct with blue background tint"
  status: failed
  reason: "User reported: Veut bordure bleu foncé au lieu du fond teinté. Enlever le check vert en bas à droite de la carte active. Ajouter feedback de chargement (animation préparation) quand on switch de modèle car le switch peut prendre 1-2s et l'utilisateur ne sait pas si le clic a été pris en compte."
  severity: major
  test: 6
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
