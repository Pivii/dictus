# Politique de confidentialité — Dictus

*Dernière mise à jour : 17 mars 2026*

## Résumé

Dictus est un clavier iOS de dictée vocale **100 % hors ligne**. Aucune donnée vocale, aucun texte dicté et aucune frappe ne quittent votre appareil. Jamais.

## Ce que fait Dictus

Dictus convertit votre voix en texte directement sur votre iPhone grâce à WhisperKit (Apple CoreML). Tout le traitement se fait localement, sans connexion internet.

## Pourquoi Dictus demande l'Accès complet

L'extension clavier iOS nécessite l'autorisation « Accès complet » (Full Access) **uniquement** pour accéder au microphone depuis le clavier. Sans cette autorisation, iOS interdit l'accès au micro dans une extension clavier.

Dictus n'utilise **aucune** des autres fonctionnalités rendues possibles par l'Accès complet :
- **Pas d'accès réseau** — aucune requête HTTP, aucun envoi de données
- **Pas de lecture du presse-papiers** — le contenu copié reste privé
- **Pas d'enregistrement des frappes** — seul le texte dicté est inséré
- **Pas d'accès aux contacts, à la localisation ou aux photos**

## Données stockées localement

Les seules données enregistrées sur votre appareil sont :
- **Préférences utilisateur** — langue, modèle sélectionné, réglages (via App Group UserDefaults)
- **Fichiers de modèles** — modèles de reconnaissance vocale téléchargés (WhisperKit CoreML)
- **Journaux de débogage** — logs techniques pour diagnostiquer les problèmes (aucun contenu de transcription)
- **Historique de dictée** — vos 200 dernières transcriptions, texte uniquement, jamais l'audio. Vous pouvez l'effacer à tout moment depuis Réglages > Transcription > Effacer l'historique

Ces données ne quittent jamais votre appareil sauf si vous choisissez explicitement d'exporter les logs de débogage.

## Collecte de données

**Dictus ne collecte aucune donnée.**

- Pas d'analytiques
- Pas de suivi (tracking)
- Pas de SDK tiers collectant des données
- Pas de publicité

L'étiquette de confidentialité App Store de Dictus est : **« Données non collectées »**.

## Sécurité

Toutes les données restent sur votre appareil. Il n'y a pas de serveur Dictus, pas de base de données cloud, pas de compte utilisateur.

## Contact

Pour toute question relative à la confidentialité :
**pierre@pivi.solutions**

---

# Privacy Policy — Dictus

*Last updated: March 17, 2026*

## Summary

Dictus is an iOS voice dictation keyboard that works **100% offline**. No voice data, no transcribed text, and no keystrokes ever leave your device. Period.

## What Dictus does

Dictus converts your voice to text directly on your iPhone using WhisperKit (Apple CoreML). All processing happens locally, with no internet connection required.

## Why Dictus requests Full Access

The iOS keyboard extension requires "Full Access" permission **solely** to access the microphone from the keyboard. Without this permission, iOS blocks microphone access in keyboard extensions.

Dictus does **not** use any of the other capabilities that Full Access enables:
- **No network access** — no HTTP requests, no data transmission
- **No clipboard reading** — your copied content stays private
- **No keystroke logging** — only dictated text is inserted
- **No access to contacts, location, or photos**

## Data stored locally

The only data saved on your device:
- **User preferences** — language, selected model, settings (via App Group UserDefaults)
- **Model files** — downloaded speech recognition models (WhisperKit CoreML)
- **Debug logs** — technical logs for diagnosing issues (no transcription content)
- **Dictation history** — your last 200 transcriptions, text only, never the audio. You can erase it at any time from Settings > Transcription > Clear history

This data never leaves your device unless you explicitly choose to export debug logs.

## Data collection

**Dictus collects no data.**

- No analytics
- No tracking
- No third-party SDKs collecting data
- No advertising

Dictus's App Store privacy nutrition label is: **"Data Not Collected"**.

## Security

All data stays on your device. There is no Dictus server, no cloud database, no user account.

## Contact

For any privacy-related questions:
**pierre@pivi.solutions**
