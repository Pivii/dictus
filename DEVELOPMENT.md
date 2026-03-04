# Dictus — Guide de développement iOS

> Ce document couvre l'ensemble du cycle de développement iOS pour Dictus : setup de l'environnement, workflow quotidien, tests sur device, distribution en bêta via TestFlight, et publication sur l'App Store.

---

## Table des matières

1. [Environnement de développement](#1-environnement-de-développement)
2. [Structure du projet Xcode](#2-structure-du-projet-xcode)
3. [Workflow de développement quotidien](#3-workflow-de-développement-quotidien)
4. [Tester sur device physique](#4-tester-sur-device-physique)
5. [Débugger la keyboard extension](#5-débugger-la-keyboard-extension)
6. [Utiliser Claude Code efficacement](#6-utiliser-claude-code-efficacement)
7. [Déploiement bêta — TestFlight](#7-déploiement-bêta--testflight)
8. [Publication App Store](#8-publication-app-store)
9. [Checklist par sprint](#9-checklist-par-sprint)

---

## 1. Environnement de développement

### Prérequis Mac

| Outil | Version minimale | Installation |
|---|---|---|
| macOS | Sequoia 15+ (recommandé pour iOS 26 SDK) | Mise à jour système |
| Xcode | 16+ | Mac App Store |
| Swift | 5.9+ | Inclus dans Xcode |
| Git | Toute version récente | `brew install git` |
| Homebrew | Toute version | [brew.sh](https://brew.sh) |

### Setup initial (à faire une seule fois)

```bash
# 1. Installer Homebrew si pas déjà présent
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Installer les outils CLI utiles
brew install git swiftlint

# 3. Cloner le repo
git clone https://github.com/[username]/dictus.git
cd dictus

# 4. Ouvrir le projet dans Xcode
open Dictus.xcodeproj
```

### Apple Developer Account

- **Compte gratuit** : suffit pour tester sur ton propre iPhone via USB. Limites : pas de TestFlight, certificat expire tous les 7 jours.
- **Compte payant ($99/an)** : nécessaire pour TestFlight et App Store. À créer sur [developer.apple.com](https://developer.apple.com) avant le Sprint 7.

Pour ajouter ton compte dans Xcode :
`Xcode → Settings → Accounts → +`

---

## 2. Structure du projet Xcode

### Créer le projet

Dictus utilise **2 targets** dans le même projet Xcode :

```
File → New → Project → App
  Name: Dictus
  Bundle ID: com.pivi.dictus
  Interface: SwiftUI
  Language: Swift
```

Puis ajouter la keyboard extension :
```
File → New → Target → Custom Keyboard Extension
  Name: DictusKeyboard
  Bundle ID: com.pivi.dictus.keyboard
```

### App Group — partage de données entre les deux targets

L'App Group est le mécanisme iOS qui permet à l'app principale et à la keyboard extension de partager des données (modèles Whisper, préférences, historique).

```
# Dans Xcode, pour CHAQUE target (DictusApp + DictusKeyboard) :
Signing & Capabilities → + Capability → App Groups
→ Ajouter : group.com.pivi.dictus
```

Utilisation dans le code :

```swift
// Lire/écrire des préférences partagées
let defaults = UserDefaults(suiteName: "group.com.pivi.dictus")
defaults?.set("small", forKey: "activeModel")

// Chemin vers les modèles partagés
let containerURL = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.com.pivi.dictus")!
let modelsPath = containerURL.appendingPathComponent("models")
```

### Capabilities requises

| Capability | Target | Raison |
|---|---|---|
| App Groups | DictusApp + DictusKeyboard | Partage données/modèles |
| Microphone | DictusApp | Test dictation dans l'app |
| `RequestsOpenAccess` | DictusKeyboard | Micro dans le clavier |

Dans `DictusKeyboard/Info.plist` :
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>RequestsOpenAccess</key>
        <true/>
    </dict>
</dict>
```

### Ajouter WhisperKit via Swift Package Manager

```
File → Add Package Dependencies
URL: https://github.com/argmaxinc/WhisperKit.git
Version: 0.9.0 ou plus récent
Targets: DictusApp + DictusKeyboard
```

---

## 3. Workflow de développement quotidien

### Le cycle de base

```
Claude Code génère / modifie du code Swift
        ↓
Tu copies les fichiers dans le projet Xcode
(ou Claude Code opère directement sur les fichiers)
        ↓
Cmd+B → Build dans Xcode
        ↓
Erreur de compilation ? → Copier l'erreur → Renvoyer à l'agent
        ↓
Feature prête → Test sur simulateur (features sans micro)
        ↓
Feature avec micro / keyboard → Test sur iPhone physique
```

### Raccourcis Xcode essentiels

| Raccourci | Action |
|---|---|
| `Cmd+B` | Build |
| `Cmd+R` | Build + Run (simulateur ou device) |
| `Cmd+U` | Run tests |
| `Cmd+Shift+K` | Clean build folder (résout 50% des bugs bizarres) |
| `Cmd+.` | Stop |
| `Cmd+Shift+Y` | Afficher/masquer la console de debug |
| `Cmd+/` | Commenter/décommenter |
| `Ctrl+I` | Re-indenter le code sélectionné |

### Simulateur vs Device physique

| Feature | Simulateur | Device physique |
|---|---|---|
| UI SwiftUI | ✅ | ✅ |
| Navigation, settings | ✅ | ✅ |
| Microphone | ❌ | ✅ |
| Keyboard extension | ⚠️ Partiel | ✅ |
| WhisperKit / Core ML | ⚠️ Lent | ✅ |
| Performance réelle | ❌ | ✅ |

**Règle pratique** : utilise le simulateur pour tout ce qui est UI et navigation. Dès que tu touches au micro, à WhisperKit ou au keyboard extension, branche ton iPhone.

### Gérer les branches Git

```bash
# Nouvelle feature
git checkout -b feature/smart-model-routing

# Commit régulier (après chaque bloc fonctionnel)
git add .
git commit -m "feat: add adaptive model switching based on audio duration"

# Merge dans main quand la feature est testée
git checkout main
git merge feature/smart-model-routing
```

---

## 4. Tester sur device physique

### Première connexion

1. Brancher l'iPhone en USB
2. Sur l'iPhone : **Faire confiance à cet ordinateur** quand la popup apparaît
3. Dans Xcode : sélectionner ton iPhone dans la barre de target (en haut à gauche)
4. `Cmd+R` → Xcode installe et lance l'app sur le téléphone

### Ajouter le clavier Dictus sur l'iPhone

Après chaque installation :
```
Réglages → Général → Clavier → Claviers → Ajouter un clavier
→ Dictus → Activer "Accès complet"
```

> ⚠️ **L'accès complet doit être réactivé après chaque reinstallation depuis Xcode.** C'est normal, iOS révoque les permissions à chaque nouvelle installation signée en développement.

### Tester la keyboard extension

1. Ouvrir n'importe quelle app avec un champ texte (Notes, Messages, Safari...)
2. Appuyer sur le bouton globe 🌐 pour changer de clavier → sélectionner Dictus
3. Tester la dictation

### Astuce : tester sans débrancher le câble

Une fois l'app installée une première fois en USB, tu peux activer le **wireless debugging** :
```
Window → Devices and Simulators → [ton iPhone]
→ Connect via Network ✓
```
Ensuite tu peux débrancher le câble et continuer à déployer en Wi-Fi.

---

## 5. Débugger la keyboard extension

### Le principal problème : les logs

Les keyboard extensions tournent dans un processus séparé. Les `print()` et logs n'apparaissent pas dans la console Xcode par défaut.

**Solution — attacher le debugger à l'extension :**

```
Debug → Attach to Process → DictusKeyboard
```

Faire ça *après* avoir ouvert un champ texte et activé le clavier Dictus sur l'iPhone.

### Erreur de mémoire (crash silencieux)

Si l'extension crash sans message d'erreur clair, c'est souvent un dépassement mémoire (~50MB). Vérifier avec Instruments :

```
Product → Profile → Allocations
→ Sélectionner le process DictusKeyboard
→ Surveiller le pic mémoire au moment de la transcription
```

Modèles autorisés dans l'extension : **tiny, base, small uniquement.**

### Erreur "Full Access not granted"

Si le micro ne fonctionne pas dans l'extension :
```swift
// Vérifier dans le code
let hasFullAccess = textDocumentProxy.hasFullAccess
// Si false → guider l'utilisateur vers les réglages
```

### Erreurs de compilation fréquentes en keyboard extension

```
// ❌ Erreur : UIApplication non disponible dans l'extension
UIApplication.shared.open(url)

// ✅ Correct : passer par l'app principale ou App Group
// Les extensions n'ont pas accès à UIApplication.shared
```

---

## 6. Utiliser Claude Code efficacement

### Workflow recommandé

Claude Code peut opérer directement sur les fichiers de ton repo local. Le workflow optimal :

```bash
# Dans le dossier du projet
claude  # Lancer Claude Code

# Exemples de prompts efficaces
"Crée le fichier DictusCore/ModelRoutingConfig.swift avec 
 la struct ModelRoutingConfig selon les specs du PRD"

"Dans DictusKeyboard/TranscriptionEngine.swift, implémente 
 la fonction resolveModel() décrite dans le PRD section 7.2"

"Fix cette erreur Xcode : [coller l'erreur complète]"
```

### Ce que Claude Code fait bien

- Générer des fichiers Swift complets à partir des specs du PRD
- Implémenter des protocoles et extensions boilerplate
- Écrire les tests unitaires pour DictusCore
- Refactorer du code existant que tu lui fournis
- Débugger à partir des messages d'erreur Xcode

### Ce qui nécessite ton intervention

- Valider que le code compile (`Cmd+B`)
- Tester sur device physique
- Résoudre les erreurs de signing / provisioning profile
- Décisions d'architecture qui ne sont pas dans le PRD

### Donner du contexte à l'agent

Quand tu démarres une session Claude Code, fournis toujours :

```
# Toujours avoir dans le repo :
- PRD.md          → specs complètes
- DEVELOPMENT.md  → ce fichier
- CLAUDE.md       → instructions spécifiques pour l'agent (voir ci-dessous)
```

### Créer un CLAUDE.md pour les agents

Fichier à la racine du repo, lu automatiquement par Claude Code :

```markdown
# CLAUDE.md

## Projet
Dictus — iOS keyboard extension pour dictation vocale offline (WhisperKit)

## Stack
- Swift 5.9+ / SwiftUI
- WhisperKit (argmaxinc) via SPM
- App Group: group.com.pivi.dictus
- Minimum iOS: 16.0

## Conventions
- Nommage : camelCase pour variables, PascalCase pour types
- Un fichier = une responsabilité
- Pas de forceUnwrap (!) sauf cas justifié avec commentaire
- Commentaires en anglais, UI strings en français

## Contraintes importantes
- DictusKeyboard : mémoire max ~50MB → tiny/base/small uniquement
- Pas d'UIApplication.shared dans l'extension
- Toutes les données partagées passent par App Group

## Fichiers clés
- DictusCore/ModelRoutingConfig.swift → config Smart Model Routing
- DictusKeyboard/TranscriptionEngine.swift → intégration WhisperKit
- DictusKeyboard/TextInserter.swift → textDocumentProxy
```

---

## 7. Déploiement bêta — TestFlight

TestFlight est la plateforme d'Apple pour distribuer des bêtas. Nécessite un **compte Developer payant ($99/an)**.

### Setup App Store Connect

1. Aller sur [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. `Mes apps → +` → Créer une nouvelle app
   - Plateforme : iOS
   - Nom : Dictus
   - Bundle ID : com.pivi.dictus
   - SKU : dictus-ios (identifiant interne)

### Créer un build pour TestFlight

Dans Xcode :

```
1. Sélectionner "Any iOS Device" comme target (pas le simulateur)
2. Product → Archive
   → Xcode compile une version release et ouvre l'Organizer
3. Dans l'Organizer :
   Distribute App → App Store Connect → Upload
   → Suivre les étapes (signing automatique recommandé)
```

Le build apparaît dans App Store Connect après 5-15 minutes de traitement.

### Distribuer aux testeurs

**Testeurs internes** (toi + équipe, jusqu'à 100 personnes) :
```
App Store Connect → TestFlight → Testeurs internes
→ Ajouter par email Apple ID
→ Disponible immédiatement, pas de review Apple
```

**Testeurs externes** (bêta publique, jusqu'à 10 000 personnes) :
```
App Store Connect → TestFlight → Groupes externes → +
→ Soumettre le build pour Beta App Review (1-2 jours)
→ Créer un lien public ou inviter par email
```

### Automatiser avec GitHub Actions

Pour générer un build TestFlight automatiquement à chaque push sur `main` :

```yaml
# .github/workflows/testflight.yml
name: Deploy to TestFlight

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      
      - name: Install Fastlane
        run: gem install fastlane
      
      - name: Deploy to TestFlight
        env:
          APP_STORE_CONNECT_API_KEY: ${{ secrets.ASC_API_KEY }}
        run: fastlane beta
```

Avec `fastlane` configuré dans un `Fastfile` à la racine. C'est la solution recommandée pour automatiser le signing et l'upload.

---

## 8. Publication App Store

### Avant de soumettre

**Checklist technique :**
- [ ] Tester sur iPhone 12, 14, 16 Pro (tailles d'écran différentes)
- [ ] Tester avec iOS minimum supporté (iOS 16.0)
- [ ] Vérifier que le clavier fonctionne dans : Notes, Messages, Safari, Mail
- [ ] Vérifier le comportement si Full Access refusé (dégradation gracieuse)
- [ ] Aucun crash sur 1h d'utilisation continue
- [ ] Mémoire extension < 40MB en usage normal (garder de la marge)

**Checklist App Store Connect :**
- [ ] Screenshots pour iPhone 6.7" et 5.5" (obligatoires)
- [ ] Description en français et en anglais
- [ ] Privacy Policy URL (obligatoire si "Data Not Collected")
- [ ] Note de review pour Apple (voir ci-dessous)
- [ ] Catégorie : Utilitaires
- [ ] Âge minimum : 4+

### Screenshots

Apple exige des screenshots aux dimensions exactes :

| Device | Taille | Obligatoire |
|---|---|---|
| iPhone 6.7" (iPhone 16 Pro Max) | 1320×2868 px | ✅ |
| iPhone 5.5" (iPhone 8 Plus) | 1242×2208 px | ✅ |
| iPad Pro 12.9" | 2048×2732 px | Si support iPad |

Générer depuis le simulateur Xcode (`Cmd+S` pour screenshot) ou avec [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

### Note de review pour Apple

Les keyboard extensions avec microphone + réseau sont scrutées. Inclure une note explicite dans "Notes pour les réviseurs" :

```
Dictus est un clavier iOS avec dictation vocale entièrement hors-ligne.

Points importants pour la review :

1. MICROPHONE DANS L'EXTENSION
   La keyboard extension utilise le microphone uniquement quand l'utilisateur
   appuie activement sur le bouton micro. La transcription se fait 100% sur 
   l'appareil via WhisperKit / Core ML. Aucun audio n'est envoyé à un serveur.

2. FULL ACCESS
   L'accès complet est requis pour accéder au microphone depuis l'extension.
   L'app demande cet accès uniquement dans ce but.

3. RÉSEAU (modes intelligents uniquement)
   Les appels réseau sont optionnels et uniquement déclenchés par l'utilisateur
   via les "modes intelligents" (reformatage LLM). L'utilisateur fournit sa 
   propre clé API OpenAI. Le mode STT de base est 100% offline.

4. DONNÉES
   Aucune donnée audio ou texte n'est collectée ni transmise par Dictus.
   Privacy Nutrition Label : "Data Not Collected".
```

### Processus de soumission

```
App Store Connect → Mon app → Distribution → App Store

1. Sélectionner le build TestFlight validé
2. Remplir les métadonnées (description, mots-clés, screenshots)
3. Répondre aux questions de privacy
4. Submit for Review
```

Délai de review Apple : **1-3 jours ouvrés** en général. Peut aller jusqu'à 7 jours pour une première soumission.

### Si la review est rejetée

Les rejets les plus fréquents pour ce type d'app :

| Motif | Solution |
|---|---|
| Guideline 2.5.4 — Extension does not function as described | Améliorer la note de review, fournir une vidéo demo |
| Guideline 5.1.1 — Data collection not disclosed | Vérifier le Privacy Nutrition Label |
| Guideline 4.3 — Duplicate app | Mettre en avant les différenciateurs (AZERTY, offline, open source) |

---

## 9. Checklist par sprint

### Sprint 1 — Setup projet

- [ ] Créer le projet Xcode avec les 2 targets (DictusApp + DictusKeyboard)
- [ ] Configurer l'App Group `group.com.pivi.dictus`
- [ ] Ajouter WhisperKit via SPM
- [ ] Vérifier que le build compile sans erreur (`Cmd+B`)
- [ ] Créer le repo GitHub et pusher le projet initial
- [ ] Ajouter `CLAUDE.md` à la racine

### Sprint 2 — Main App

- [ ] Onboarding (3 écrans + step keyboard setup + step Full Access)
- [ ] Settings (modèle, layout clavier, langue, Smart Model Routing)
- [ ] Model Manager (download, progression, delete, storage indicator)
- [ ] Test screen in-app avec dictation fonctionnelle

### Sprint 3 — Keyboard Extension

- [ ] Layout AZERTY complet en SwiftUI
- [ ] Layout QWERTY (toggle depuis les settings)
- [ ] Mic button avec états (idle / recording / transcribing)
- [ ] Zone preview transcription
- [ ] Build sans erreur + test d'ouverture sur device

### Sprint 4 — Transcription STT

- [ ] AVFoundation recording dans l'extension
- [ ] WhisperKit chargé depuis l'App Group (chemin partagé)
- [ ] Transcription fonctionnelle sur un vocal court (< 5s)
- [ ] Suppression des mots de remplissage (euh, hm, um...)
- [ ] Smart Model Routing (switch base → small selon durée)

### Sprint 5 — Insertion et UX

- [ ] Auto-insert via `textDocumentProxy.insertText()`
- [ ] Zone preview éditable inline
- [ ] Undo (bouton + shake gesture)
- [ ] Feedback haptique (début enregistrement, fin, insertion)
- [ ] Waveform animé pendant l'enregistrement

### Sprint 6 — Polish et tests

- [ ] Test sur iPhone 12, 14, 16 Pro
- [ ] Test dans : Notes, Messages, Safari, Mail, WhatsApp
- [ ] Gestion des champs sécurisés (password fields)
- [ ] Gestion du mode paysage
- [ ] Profiling mémoire (< 40MB dans l'extension)
- [ ] Pas de crash sur 30 minutes d'utilisation
- [ ] Validation French STT : phrases FR avec termes EN

---

## Ressources

- [Apple — Custom Keyboard Extensions](https://developer.apple.com/documentation/uikit/keyboards_and_input/creating_a_custom_keyboard)
- [WhisperKit Documentation](https://github.com/argmaxinc/WhisperKit)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
- [Fastlane Documentation](https://docs.fastlane.tools)
- [Human Interface Guidelines — iOS 26](https://developer.apple.com/design/human-interface-guidelines)

---

*Dictus DEVELOPMENT.md — PIVI Solutions — 2026*
