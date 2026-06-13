# AGENTS.md — Dictus

## Projet

Dictus — iOS keyboard extension pour dictation vocale offline (WhisperKit).
Voir PRD.md pour les specs complètes et DEVELOPMENT.md pour le guide de développement.

## Stack

- Swift 5.9+ / SwiftUI
- WhisperKit (argmaxinc) via SPM
- FluidAudio (Parakeet STT) via SPM — DictusApp only
- App Group: group.solutions.pivi.dictus
- Minimum iOS: 17.0
- Design: iOS 26 Liquid Glass

## Targets Xcode

- **DictusApp** — App principale (onboarding, settings, model manager)
- **DictusKeyboard** — Keyboard Extension (clavier custom + dictation)
- **DictusCore** — Framework partagé (App Group, modèles, préférences)

## Conventions

- Nommage : camelCase pour variables/fonctions, PascalCase pour types/structs
- Un fichier = une responsabilité
- Pas de forceUnwrap (!) sauf cas justifié avec commentaire
- Commentaires en anglais dans le code
- UI strings : français (langue principale) + anglais

## Contraintes importantes

- DictusKeyboard : mémoire max ~50MB → modèles tiny/base/small uniquement
- Pas d'UIApplication.shared dans l'extension keyboard
- Toutes les données partagées passent par App Group
- RequestsOpenAccess = true dans Info.plist de l'extension (pour le micro)

## Contexte utilisateur

- Pierre est débutant en Swift/SwiftUI — expliquer les concepts clés au fur et à mesure
- Toujours expliquer le "pourquoi" derrière les choix d'architecture iOS
- Signaler les patterns Swift importants quand ils sont utilisés pour la première fois

## Brand & Design

Le brand kit complet est dans `assets/brand/dictus-brand-kit.html`.
Il contient les SVG du logo, tous les codes couleur et les gradients.

Quand tu as besoin de générer des assets visuels :

1. Lire le HTML pour extraire les valeurs exactes
2. Générer les fichiers SVG dans `assets/brand/`
3. Générer les PNG iOS dans `Dictus/Assets.xcassets/AppIcon.appiconset/`

### Couleurs principales (résumé rapide)

- Background : #0A1628
- Accent : #3D7EFF
- Accent highlight : #6BA3FF
- Surface : #161C2C
- Recording : #EF4444
- Smart mode : #8B5CF6
- Success : #22C55E

### Logo

3 barres verticales asymétriques (hauteurs : 18pt / 42pt / 27pt)
Barre centrale = dégradé #6BA3FF → #2563EB
Barres latérales = blanc à 45% et 65% d'opacité
Fond icône = dégradé #0D2040 → #071020 à 135°
Border radius barres = 4.5pt

## Agent skills

### Issue tracker

Issues and PRDs live as GitHub issues in `getdictus/dictus-ios`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root (created lazily by `/grill-with-docs`). See `docs/agents/domain.md`.
