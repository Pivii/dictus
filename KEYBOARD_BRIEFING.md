# Dictus — Rebuild du clavier iOS natif

> Document de référence pour Claude Code.
> Objectif : reconstruire les features du clavier Apple standard dans la keyboard extension Dictus.
> Tout ce qui est dans ce document doit être implémenté ou planifié.

---

## Contexte

Apple ne partage aucune feature native du clavier système avec les claviers tiers.
Tout doit être recodé from scratch via les APIs publiques.

**Périmètre de ce document : clavier uniquement. La transcription vocale est hors scope.**

---

## Features à implémenter

### 1. Trackpad spacebar — déplacement du curseur

Long press sur la spacebar → mode trackpad pour positionner le curseur précisément.

**Comportement attendu :**
- Long press > 0.3s sur la spacebar → les labels des touches disparaissent
- L'utilisateur glisse son doigt → le curseur se déplace dans le champ texte
- Relâcher → les touches réapparaissent, curseur positionné

**Implémentation :**
```swift
// SpacebarView.swift

private var lastTrackpadX: CGFloat = 0

let longPress = UILongPressGestureRecognizer(
    target: self,
    action: #selector(handleTrackpad(_:))
)
longPress.minimumPressDuration = 0.3
spacebarButton.addGestureRecognizer(longPress)

@objc func handleTrackpad(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
        lastTrackpadX = gesture.location(in: view).x
        setTrackpadMode(true)   // griser touches, masquer labels
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

    case .changed:
        let currentX = gesture.location(in: view).x
        let delta = currentX - lastTrackpadX
        let offset = Int(delta / 8)  // 8pt = 1 caractère
        if offset != 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            lastTrackpadX = currentX
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

    case .ended, .cancelled:
        setTrackpadMode(false)  // restaurer touches

    default: break
    }
}
```

---

### 2. Long press delete — suppression continue

Maintien du doigt sur ← supprime les caractères un par un, en accélérant.

**Comportement attendu :**
- Tap simple → supprime 1 caractère
- Long press → supprime en continu, accélère après 500ms

**Implémentation :**
```swift
// DeleteKey.swift

private var deleteTimer: Timer?
private var deleteCount = 0

let longPress = UILongPressGestureRecognizer(
    target: self,
    action: #selector(handleDeleteLongPress(_:))
)
longPress.minimumPressDuration = 0.4
deleteButton.addGestureRecognizer(longPress)

@objc func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
        deleteCount = 0
        startDeleteTimer()
    case .ended, .cancelled:
        deleteTimer?.invalidate()
        deleteTimer = nil
    default: break
    }
}

private func startDeleteTimer() {
    deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        self.textDocumentProxy.deleteBackward()
        self.deleteCount += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Accélération : après 10 suppressions, passer en suppression mot entier
        if self.deleteCount > 10 {
            self.textDocumentProxy.deleteWordBackward()
        }
    }
}
```

---

### 3. Autocapitalisation

Majuscule automatique en début de phrase et en début de champ texte.

**C'est quoi ?** Le clavier Apple met automatiquement le shift actif après un point, un point d'exclamation, un point d'interrogation, ou quand le champ est vide. Sur un clavier custom, ça ne se fait pas tout seul — il faut lire le texte avant le curseur et activer le shift manuellement.

**Comportement attendu :**
- Champ vide → shift actif
- Après `. ` `! ` `? ` → shift actif
- Milieu de phrase → shift inactif

**Implémentation :**
```swift
// AutocapHandler.swift

func shouldCapitalize(proxy: UITextDocumentProxy) -> Bool {
    if proxy.autocapitalizationType == .none { return false }

    let before = proxy.documentContextBeforeInput ?? ""

    if before.isEmpty        { return true }
    if before.hasSuffix(". ") { return true }
    if before.hasSuffix("! ") { return true }
    if before.hasSuffix("? ") { return true }
    if before.hasSuffix("\n") { return true }

    return false
}

// Appeler après chaque frappe pour mettre à jour l'état visuel du shift
func updateShiftState() {
    let shouldCap = shouldCapitalize(proxy: textDocumentProxy)
    keyboardView.setShiftActive(shouldCap)
}
```

---

### 4. Accents long press — AZERTY

Long press sur une touche → popover avec les variantes accentuées, comme sur le clavier Apple.

**Comportement attendu :**
- Long press sur `e` → popover `é è ê ë ə`
- Glisser sur une lettre → la sélectionner (surbrillance)
- Relâcher → insérer le caractère choisi

**Map complète des accents AZERTY français :**
```swift
// AccentMap.swift

let accentMap: [Character: [Character]] = [
    "e": ["é", "è", "ê", "ë", "ə"],
    "a": ["à", "â", "ä", "æ"],
    "u": ["ù", "û", "ü"],
    "i": ["î", "ï"],
    "o": ["ô", "ö", "œ"],
    "c": ["ç"],
    // Majuscules
    "E": ["É", "È", "Ê", "Ë"],
    "A": ["À", "Â", "Ä", "Æ"],
    "U": ["Ù", "Û", "Ü"],
    "I": ["Î", "Ï"],
    "O": ["Ô", "Ö", "Œ"],
    "C": ["Ç"],
]
```

**Implémentation du popover :**
```swift
// AccentPopover.swift

struct AccentPopover: View {
    let variants: [Character]
    let onSelect: (Character) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(variants, id: \.self) { char in
                Text(String(char))
                    .frame(width: 36, height: 44)
                    .background(Color(.systemBackground))
                    .onTapGesture { onSelect(char) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
    }
}
```

---

### 5. Retour haptique

Feedback sur chaque interaction clavier. Le clavier Apple vibre légèrement à chaque touche — sans ça le clavier custom semble "mort".

```swift
// HapticEngine.swift

struct HapticEngine {
    static func keyTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func shift() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func returnKey() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// Appel sur chaque frappe
HapticEngine.keyTap()
```

---

### 6. Son de frappe

```swift
// La vue principale du clavier doit implémenter UIInputViewAudioFeedback
class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { return true }
}

// Sur chaque frappe
UIDevice.current.playInputClick()
```

---

## Features exclues du scope

| Feature | Raison |
|---|---|
| Swipe-to-type | Algorithme très complexe (path matching + Levenshtein) — hors scope |
| Autocomplete / suggestions | Complexe (UILexicon + moteur prédiction) — prévu V1+ |
| Sélection de texte avancée | Double tap mot, triple tap paragraphe — prévu V2 |

---

## Performance — règles à respecter

**Règle 1 — Pas de re-render global**
Chaque touche est un composant SwiftUI isolé. Une frappe ne doit re-render que la touche concernée.

```swift
// ✅ Correct
struct KeyView: View {
    let model: KeyModel
    // Ne re-render que si KeyModel change
}

// ❌ Incorrect — état global dans le parent qui force un re-render complet
@State var lastKey: String = ""
```

**Règle 2 — `drawingGroup()` sur les vues complexes**
```swift
KeyboardView()
    .drawingGroup() // Rasterise en texture Metal → rendu plus fluide
```

**Règle 3 — Objectif mémoire**
Clavier seul (sans transcription) : < 20MB.
Vérifier avec : `Xcode → Product → Profile → Allocations → process DictusKeyboard`

---

## Checklist de vérification

Audite le code actuel et coche chaque point. Pour chaque point non coché, implémenter.

- [ ] Trackpad spacebar avec `adjustTextPosition(byCharacterOffset:)`
- [ ] Long press delete avec Timer 100ms + accélération après 10 suppressions
- [ ] Autocapitalisation après `. ` `! ` `? ` et en début de champ
- [ ] Long press accents AZERTY : e/é/è/ê/ë · a/à/â/ä · u/ù/û/ü · i/î/ï · o/ô/ö/œ · c/ç
- [ ] Retour haptique sur frappe (light), shift (medium), return (medium)
- [ ] Son de frappe via `UIDevice.current.playInputClick()`
- [ ] Pas de re-render global du KeyboardView à chaque frappe
- [ ] Mémoire clavier seul < 20MB (Instruments)

---

*Dictus KEYBOARD_BRIEFING.md — PIVI Solutions — 2026*
