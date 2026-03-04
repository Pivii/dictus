# CLAUDE.md — Dictus

## Projet
Dictus — iOS keyboard extension pour dictation vocale offline (WhisperKit).
Voir PRD.md pour les specs complètes et DEVELOPMENT.md pour le guide de développement.

## Stack
- Swift 5.9+ / SwiftUI
- WhisperKit (argmaxinc) via SPM
- App Group: group.com.pivi.dictus
- Minimum iOS: 16.0
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
