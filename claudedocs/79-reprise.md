# Reprise #79 — état au 2026-08-24, 16 h

À coller dans une session neuve. Tout ce qui compte est ici ou dans les liens ; rien d'important ne vit dans un contexte d'agent.

## Où en est le code

| Branche | PR | État |
|---|---|---|
| `feature/79-smart-modes-keyboard` → `9d1f4bf` | #394 | Bloc B. **Validé sur device.** Installé sur l'iPhone. |
| `feature/79-smart-modes-app` → `1eab57b` | #395 | Bloc C. Écrans jamais vus, cf. plus bas. |

`9d1f4bf` est identique à `b20ea6e` — c'est le revert de deux tentatives visuelles refusées à vue (détail plus bas). `git diff b20ea6e 9d1f4bf` est vide.

**Ce qui marche, testé sur iPhone 15 Pro Max :** tap simple → enregistre ; appui long → éventail avec haptique ; glissé + relâchement → arme le mode ET démarre l'enregistrement ; retour sur le micro → annule ; le mode survit à la fermeture du clavier ; 16 dictées Smart Mode de bout en bout.

## La question ouverte : le violet

**Position de Pierre, ferme :** le violet doit **sortir de la fonctionnalité**, pas être dosé. Il y en a à trois endroits aujourd'hui et les trois le gênent :

1. l'anneau ou le remplissage du pill micro quand un mode est armé ;
2. le libellé `✦ → EN` au centre de la barre de suggestion ;
3. la capsule de surlignage dans l'éventail.

Deux tentatives ont été refusées à vue, ne les reproposez pas :

- **Pill entièrement violet** (`#8B5CF6` en remplissage) — « ça dénature l'app ».
- **Anneau violet 3 pt autour d'un pill bleu** — « vraiment pas beau », lu comme un contour collé sur le bouton.

Une idée de Pierre, à creuser mais **pas** telle quelle : rester dans la palette de la waveform (gris et bleus), micro gris pour Normal, micro bleu pour Smart Mode. Argumentée contre dans `claudedocs/79-smart-mode-visual-coherence.md` §1, et l'argument tient : Dictus affiche déjà un micro grisé qui veut dire « tu ne peux pas dicter » (`fullAccessBar` à 0,4 d'opacité, `MicButtonDisabled.swift`), donc l'état par défaut aurait l'air cassé.

**Le vrai problème n'a pas été résolu :** il faut un signal « un mode est armé » qui soit lisible du coin de l'œil et qui appartienne au langage visuel de Dictus. Ni le violet ni un anneau ne conviennent. Le document de design a raison sur le diagnostic (c'est une question de dose et de placement) et tort sur sa conclusion.

## L'autre défaut visuel, réel et toujours ouvert

Le texte de l'app hôte **se lit à travers les rangées de l'éventail** — visible sur les captures du 2026-08-24. Cause : le conteneur du clavier est translucide et ce sont les *touches* qui donnent normalement une surface opaque à l'œil ; l'éventail les remplace par du texte sur rien.

`dictusGlass(in: Rectangle())` a été essayé et **refusé** : ça produit un bloc plus clair que le clavier, avec des arêtes nettes en haut et en bas — « une sorte de carré » posé par-dessus. Le correctif doit se fondre dans le clavier, pas s'y superposer.

## Ce qui bloque la livraison, indépendamment du design

- **#393** — le harness ne sait pas exécuter un Smart Mode, donc Notes et Translate ne sont **pas mesurés**. Première preuve terrain déjà versée : une dictée française est ressortie en bullets **anglais** (1 appel sur 6), le garde-fou de langue l'a rejetée, rien n'a été inséré. Le pipeline a bien fonctionné ; c'est le prompt Notes qui dérive. À traiter avant toute livraison à un utilisateur.
- **#392** — traité dans le bloc C (#395).
- **#397** — **les Smart Modes sont inarmables sous VoiceOver.** L'armement est un geste, et VoiceOver l'intercepte. Ça change le rôle de la liste de modes du bloc C : elle devient une surface d'armement obligatoire, pas seulement d'épinglage. Les deux branches doivent s'accorder.
- **#396** — le pill micro mesure 1,30:1 pendant la transcription sur clavier clair, son glyphe blanc 1,95:1. Il disparaît pendant l'attente la plus longue du produit.
- **Décision 2 du commentaire bloc A sur #79** — le cache de sessions `LanguageModelSession` monte à 14 entrées dans un process de ~50 Mo. Jamais mesuré sur device avec plusieurs modes cyclés.

## Deux choses jamais vérifiées visuellement

Les écrans du bloc C (#395) — liste de modes, carte paywall marquée. Ils sont derrière `PremiumFlags.paywallVisible = false` et l'onboarding exige un modèle de 483 Mo. La logique est testée (1161 tests) ; le rendu ne l'est pas.

## Pièges de cette session, à ne pas repayer

- **Un geste SwiftUI ne survit pas à un changement de branche du `switch`** dans `KeyboardRootView`. L'identité est positionnelle. La toolbar est sortie du `switch` pour ça.
- **`LongPressGesture` vaut « un appui est en cours »**, pas « l'appui a duré ». Ouvrir sur `.first(true)` = aucun seuil. Ouvrir sur `.second`.
- **`axe touch --up` ne termine pas un `DragGesture`** SwiftUI. Utiliser un `swipe` comme dernière étape. Détaillé dans `docs/agents/simulator.md`.
- Le worktree device est `/Users/pierreviviere/dev/dictus-wt/device`, jamais le clone principal.

## Ce que je ferais maintenant

Une session neuve, **sans agent délégué**. La dernière délégation a produit un document solide dont la recommandation a été refusée d'un coup d'œil : la question n'est pas analytique, elle est itérative, et il faut la boucle build → device → regard de Pierre. Un agent ne l'a pas.

Concrètement : deux ou trois propositions de signal « mode armé », construites et installées sur le téléphone, jugées à l'œil. Pas de document préalable.
