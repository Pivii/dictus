# CLAUDE.md — Dictus

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
- L'extension keyboard atteint l'app via `extensionContext`
- La contrainte de hauteur **déclarée** du clavier est une zone interdite (#166, et trois régressions depuis)

## Git et releases

- Le travail part de `develop`, les PR ciblent `develop`. `main` est ce qui est sur l'App Store.
- `Closes #N` **n'auto-ferme pas** sur un merge dans `develop` : écrire `refs #N` et fermer l'issue à la main.
- Merge, jamais squash.
- Les trois targets partagent un numéro de version et de build. Ne jamais les bumper hors d'une coupe TestFlight (`scripts/cut-testflight.sh`).
- Une PR n'est pas validée par une CI verte : elle passe par une relecture indépendante et un test sur device avant merge.

## Build, test, lint

- Trois targets à construire : `DictusApp`, `DictusKeyboard`, `DictusCore`.
- Un worktree neuf — comme tout "Reset Package Caches" — résout les packages de zéro et exige `./scripts/patch-fluidaudio-swift5.sh` avant le premier build, sinon il échoue. Le script prend le chemin de derived data du build à venir : `./scripts/patch-fluidaudio-swift5.sh build/DerivedData` pour un build en ligne de commande avec `-derivedDataPath`, sans argument pour un build Xcode. Sans argument il ne patche que la derived data partagée d'Xcode, ce qui ne dit rien du checkout d'un worktree (#285). Il sort en erreur quand il ne trouve aucun checkout sous le chemin demandé.
- Lint : `swiftlint lint --strict`. Pas de baseline ni de fichier d'exemptions (la baseline a été supprimée en #146), donc toute violation introduite se corrige ou porte un `swiftlint:disable` avec sa raison écrite.
- Xcode régénère `Localizable.xcstrings` au build (état d'extraction `stale`, newline finale perdue). C'est du bruit de build : le jeter, jamais le committer.

### Rester headless

Pierre travaille sur cette machine : toute fenêtre qui s'ouvre lui vole le focus.

- `xcrun simctl boot <udid>` est headless, donc autorisé.
- `xcodebuild test -destination 'platform=iOS Simulator,name=...'` est la façon de lancer les tests.
- Ne pas lancer `open -a Simulator`. Si un outil ouvre une fenêtre malgré tout, `open -g` pour qu'elle ne passe pas au premier plan.
- Un agent ne peut pas valider sur device physique : ce qui l'exige part dans la liste de validation manuelle, avec les étapes exactes.
- La recette complète (boot, build, install, launch, capture, et ce que le simulateur ne peut pas montrer) est dans `docs/agents/simulator.md`.

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

Single-context — `CONTEXT.md` + `docs/adr/` at the repo root (created lazily by `/domain-modeling`). See `docs/agents/domain.md`.

### Headless simulator

Boot, build, install, launch, capture, and what a simulator cannot show. See `docs/agents/simulator.md`.
