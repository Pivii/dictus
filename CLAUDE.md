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

## Priorités

`docs/ROADMAP.md` est la file ordonnée du projet : trois voies séquentielles (1.8.2 bugs → 2.0.0 Pro → session clavier) et, dans chacune, une liste numérotée. **Le lire avant de proposer du travail, et prendre le premier item non fait de la voie active.** Le tracker trie par qualité de rédaction, pas par importance — c'est ce fichier qui porte l'ordre. `docs/RELEASE-PLAN.md` dit pourquoi les cycles sont ce qu'ils sont ; `docs/VERSIONING.md` dit comment les numéroter.

Les issues du milestone `Someday` sont hors de vue volontairement. Ne pas les remonter sans que Pierre le demande.

**`docs/ROADMAP.md` et `docs/RELEASE-PLAN.md` se committent directement sur `develop`.** Ce sont des fichiers de pilotage : ils ne compilent pas, ne cassent rien, et une PR sur eux n'a ni relecture indépendante utile ni test device — les deux seules choses qui valident une PR ici. Ils restent versionnés parce qu'un worktree ne voit que ce qui est dans git, et que ce fichier pointe dessus.

`develop` est protégé (PR requise, 2 status checks) et le compte de Pierre a le droit de contournement, donc le push passe en affichant `Bypassed rule violations`. **C'est délibéré pour ces deux fichiers et pour eux seuls** : faire tourner deux builds iOS sur une modification de markdown coûte des minutes pour zéro information, et de toute façon — la CI ne teste rien. Tout le reste, y compris la moindre ligne de Swift, passe par une PR.

## Git et releases

- Le travail part de `develop`, les PR ciblent `develop`. `main` est ce qui est sur l'App Store.
- `Closes #N` **n'auto-ferme pas** sur un merge dans `develop` : écrire `refs #N` et fermer l'issue à la main.
- Merge, jamais squash.
- Les trois targets partagent un numéro de version et de build. Ne jamais les bumper hors d'une coupe TestFlight (`scripts/cut-testflight.sh`).
- Une PR n'est pas validée par une CI verte : elle passe par une relecture indépendante et un test sur device avant merge.

## Build, test, lint

- Trois targets à construire : `DictusApp`, `DictusKeyboard`, `DictusCore`.
- Tests : `cd DictusCore && swift test`. C'est la seule suite du dépôt et elle tourne sur le Mac, sans simulateur. Depuis #301 la destination iOS Simulator passe elle aussi, mais elle exécute exactement les mêmes tests — aucun n'est réservé à iOS — en payant le boot du simulateur. Il n'y a donc jamais de raison de la préférer.
- Un worktree neuf — comme tout "Reset Package Caches" — résout les packages de zéro et exige `./scripts/patch-fluidaudio-swift5.sh` avant le premier build, sinon il échoue. Le script prend le chemin de derived data du build à venir : `./scripts/patch-fluidaudio-swift5.sh build/DerivedData` pour un build en ligne de commande avec `-derivedDataPath`, sans argument pour un build Xcode. Sans argument il ne patche que la derived data partagée d'Xcode, ce qui ne dit rien du checkout d'un worktree (#285). Il sort en erreur quand il ne trouve aucun checkout sous le chemin demandé.
- Lint : `swiftlint lint --strict`. Pas de baseline ni de fichier d'exemptions (la baseline a été supprimée en #146), donc toute violation introduite se corrige ou porte un `swiftlint:disable` avec sa raison écrite.
- Xcode régénère `Localizable.xcstrings` au build (état d'extraction `stale`, newline finale perdue). C'est du bruit de build : le jeter, jamais le committer.

### Rester headless

Pierre travaille sur cette machine : toute fenêtre qui s'ouvre lui vole le focus.

- `xcrun simctl boot <udid>` est headless, donc autorisé.
- La suite de tests n'a besoin d'aucun simulateur (`cd DictusCore && swift test`). Seuls les builds d'app en demandent un.
- Ne jamais mettre une fenêtre Simulator au premier plan : `open -a Simulator` est interdit. `open -g -a Simulator` ne l'est pas, et il est requis pour piloter l'UI (`axe` ne peut taper que si Simulator.app est attaché au device booté). Mesuré : `-g` ne change pas l'app au premier plan.
- Un agent ne peut pas valider sur device physique : ce qui l'exige part dans la liste de validation manuelle, avec les étapes exactes.
- Le simulateur se pilote au tap, au clavier et par l'arbre d'accessibilité avec `axe`. Le clavier Dictus **s'y affiche**, y prend le Full Access et y déclenche toute la chaîne clavier → app. On l'atteint en **appuyant longuement** sur le globe puis en le choisissant dans le menu : un tap simple fait défiler les claviers et saute les claviers tiers. La recette complète est dans `docs/agents/simulator.md`, qui fait autorité sur ce que le simulateur sait faire.

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
