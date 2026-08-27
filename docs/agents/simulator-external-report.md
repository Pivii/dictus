# Reference: external report on driving iOS Simulator with an agent

Received 2026-08-22 from an AI agent outside this project, filed here because its
survey of the ecosystem is useful. **It is not the authority on this machine —
`simulator.md` is**, and every measured claim below was checked against it on
2026-08-23 (Xcode 26.4.1, iOS 26.5).

## What held

- The core diagnosis. `simctl` alone has no touch injection, and concluding
  "therefore the simulator cannot be driven" is wrong. A UI automation layer is
  the missing piece.
- `describe-ui` before every interaction; prefer accessibility label or
  identifier over coordinates; re-inspect after each screen change.
- Screenshots are evidence, not the control surface.
- Adding `.accessibilityIdentifier` to controls an agent must drive.
- Section 13: `type_text` is not a test of a keyboard extension. Correct, and it
  matters more here than in most projects.
- Section 14: UI automation can drive Settings.app. Confirmed — that is exactly
  how the Dictus keyboard was enabled.

## What did not hold

- **The root cause is wrong for this machine.** The report attributes "cannot
  tap" to XcodeBuildMCP being absent or its `ui-automation` workflow disabled.
  The actual cause here was that Simulator.app had no attachment to the booted
  device. `axe` was already installed and working; it needed `open -g -a
  Simulator` after `bootstatus`. See `simulator.md` section 5.
- **Its remedy would not have fixed it.** XcodeBuildMCP bundles AXe as its UI
  automation engine. Installing it puts the same binary behind an MCP interface
  and hits the same wall for the same reason.
- **Sections 11 and 12, on the hardware keyboard, did not reproduce.** With
  `ConnectHardwareKeyboard = 1`, the software keyboard came up normally. The
  setting exists and is worth knowing; it was not the blocker.

## Verdict on XcodeBuildMCP

Not installed, deliberately. `axe` is already here and is the same engine
underneath; `xcodebuild` and `simctl` already cover build, install, launch and
logs. Adding an MCP server would add a layer, not a capability. Revisit if the
LLDB debugging tools or the project-scaffolding tools become worth it on their
own merits.

---

*Everything below is the report as received, unedited.*

---

# Rapport --- Piloter correctement iOS Simulator avec un agent IA sur macOS

**Date : 22 août 2026**\
**Objectif :** permettre à un agent local (Claude Code, Codex ou autre
agent CLI/MCP) de construire, lancer, observer et **piloter réellement**
une application iOS dans le simulateur Apple : taps, swipes, saisie,
navigation, clavier logiciel, screenshots et logs.

------------------------------------------------------------------------

## 1. Diagnostic rapide

Si l'agent sait déjà :

-   compiler l'application ;
-   démarrer un iPhone Simulator ;
-   installer/lancer l'app ;
-   prendre éventuellement une capture ;

mais affirme ensuite qu'il **ne peut pas faire de tap ou de swipe**, le
problème n'est probablement **pas une limitation fondamentale d'iOS
Simulator**.

Le point important est le suivant :

> `xcrun simctl` et `xcodebuild` seuls sont excellents pour gérer le
> simulateur, compiler, installer et lancer une app, mais ils ne
> constituent pas à eux seuls une API complète et pratique de
> manipulation tactile de l'UI.

Pour un agent, il faut lui donner une **couche d'automatisation UI**. En
2026, la solution recommandée pour ce cas est **XcodeBuildMCP**, qui
expose explicitement à l'agent les opérations de build, lancement,
inspection UI, tap, swipe/gestures, saisie, screenshots et logs.

Le dépôt OpenAI lui-même contient désormais un skill
`ios-debugger-agent` qui utilise **XcodeBuildMCP** et recommande
explicitement la boucle :

`build/run -> describe_ui -> tap/type/gesture -> screenshot -> logs -> correction`

Donc : **ne pas essayer de résoudre le problème uniquement avec
`simctl`.**

------------------------------------------------------------------------

# 2. Architecture recommandée

``` text
Agent IA
Claude Code / Codex / agent local
        |
        | MCP ou CLI
        v
XcodeBuildMCP
        |
        +--> xcodebuild
        +--> CoreSimulator / Simulator Apple
        +--> inspection accessibility/UI
        +--> tap / swipe / gesture
        +--> saisie texte
        +--> screenshots
        +--> logs
        +--> debugging
        |
        v
Application iOS simulée
```

Le simulateur reste **le simulateur officiel Apple**. XcodeBuildMCP ne
remplace pas iOS Simulator : il fournit une interface beaucoup plus
exploitable par un agent.

------------------------------------------------------------------------

# 3. Solution recommandée : XcodeBuildMCP

Projet : `getsentry/XcodeBuildMCP`

GitHub : https://github.com/getsentry/XcodeBuildMCP\
Documentation : https://xcodebuildmcp.com/

Le projet est spécifiquement conçu pour permettre à des agents IA de
travailler avec Xcode et iOS Simulator.

Fonctions utiles :

-   découverte des projets/workspaces et schemes ;
-   build ;
-   build + run ;
-   boot du simulateur ;
-   installation/lancement de l'app ;
-   screenshots ;
-   inspection de la hiérarchie UI/accessibilité ;
-   tap ;
-   long press ;
-   swipe ;
-   gestures ;
-   drag ;
-   saisie texte ;
-   boutons hardware ;
-   attente d'un état UI ;
-   capture des logs ;
-   debugging LLDB.

**Attention : les outils UI ne sont pas nécessairement activés par
défaut.** C'est une cause très plausible du problème « je peux lancer le
simulateur mais je ne peux pas tap/swipe ».

------------------------------------------------------------------------

# 4. Vérifications préalables sur le Mac

L'agent doit commencer par auditer l'environnement au lieu de supposer
qu'il est correctement configuré.

Commandes de diagnostic :

``` bash
sw_vers
xcode-select -p
xcodebuild -version
xcrun simctl list devices
xcrun simctl list runtimes
```

Vérifier que :

1.  Xcode complet est installé.
2.  `xcode-select` pointe vers le bon Xcode.
3.  Au moins un runtime iOS est installé.
4.  Au moins un simulateur iPhone existe.
5.  Le projet compile pour `iOS Simulator`.

Si nécessaire :

``` bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Ne lancer cette commande avec `sudo` qu'après avoir vérifié que
`/Applications/Xcode.app` est bien le Xcode voulu.

------------------------------------------------------------------------

# 5. Installation de XcodeBuildMCP

## Option recommandée : Homebrew

``` bash
brew tap getsentry/xcodebuildmcp
brew install xcodebuildmcp
xcodebuildmcp --help
xcodebuildmcp tools
```

L'installation Homebrew ne nécessite pas Node.js.

Alternative npm :

``` bash
npm install -g xcodebuildmcp@latest
xcodebuildmcp --help
```

Il est également possible de le lancer à la demande :

``` bash
npx -y xcodebuildmcp@latest mcp
```

------------------------------------------------------------------------

# 6. Activer impérativement l'automatisation UI

C'est probablement **le point le plus important de ce rapport**.

XcodeBuildMCP organise ses outils en workflows. Le workflow simulateur
est disponible, mais les fonctions avancées d'automatisation UI peuvent
devoir être activées.

Créer/configurer :

``` text
.xcodebuildmcp/config.yaml
```

Exemple :

``` yaml
schemaVersion: 1

enabledWorkflows:
  - simulator
  - ui-automation
  - debugging

sessionDefaults:
  platform: iOS
  useLatestOS: true
  arch: arm64
```

Puis compléter les defaults du projet quand ils sont connus, par exemple
:

``` yaml
sessionDefaults:
  workspacePath: "./MonApp.xcworkspace"
  scheme: "MonApp"
  configuration: "Debug"
  simulatorName: "iPhone 17"
  useLatestOS: true
  platform: "iOS"
  arch: "arm64"
  bundleId: "com.example.monapp"
```

Utiliser `projectPath` à la place de `workspacePath` pour un
`.xcodeproj`.

Après modification des workflows, **redémarrer/recharger la session de
l'agent/MCP** afin que les nouveaux outils soient exposés.

Configuration de référence officielle XcodeBuildMCP :

https://github.com/getsentry/XcodeBuildMCP/blob/main/config.example.yaml

Elle montre notamment :

``` yaml
enabledWorkflows: ['simulator', 'ui-automation', 'debugging']
```

------------------------------------------------------------------------

# 7. Connecter XcodeBuildMCP à l'agent

Pour un client MCP, le serveur à lancer est simplement :

``` bash
xcodebuildmcp mcp
```

Une configuration MCP typique ressemble conceptuellement à :

``` json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "xcodebuildmcp",
      "args": ["mcp"]
    }
  }
}
```

XcodeBuildMCP documente des configurations pour **Claude Code et
Codex**. L'agent doit utiliser la documentation correspondant à son
client plutôt que d'inventer une configuration.

Documentation clients :

https://xcodebuildmcp.com/docs/clients

Après connexion, vérifier que l'agent voit réellement les outils UI.

Il doit disposer de capacités correspondant au minimum à :

``` text
snapshot_ui / describe_ui
tap
swipe / gesture
type_text
screenshot
```

Selon la version, les noms exacts peuvent légèrement évoluer.

Si `tap`, `gesture`, `swipe` ou `type_text` n'apparaissent pas, **ne pas
conclure que le simulateur ne sait pas le faire** : vérifier d'abord que
`ui-automation` est activé et que le client MCP a rechargé ses outils.

------------------------------------------------------------------------

# 8. Comment l'agent doit naviguer dans l'application

## Mauvaise stratégie

Ne pas faire :

``` text
Je vois approximativement le bouton sur un screenshot.
Je suppose qu'il est à x=173, y=412.
Je clique au hasard.
```

Cela devient fragile dès qu'un écran, une taille d'iPhone ou le clavier
change.

## Bonne stratégie

À chaque nouvel écran :

``` text
1. snapshot_ui / describe_ui
2. identifier l'élément par accessibility id ou label
3. tap sur cet élément
4. attendre que l'UI change
5. snapshot_ui ou screenshot pour vérifier
```

Le skill iOS publié dans le dépôt OpenAI recommande précisément de faire
`describe_ui` avant l'interaction et de préférer **id/label** aux
coordonnées.

Exemple conceptuel :

``` text
describe_ui

-> détecte :
   Button
   label: "Settings"
   ...

tap(label="Settings")

wait_for_ui(...)

screenshot
```

Pour changer de page avec un geste :

``` text
gesture(scroll...)
```

ou :

``` text
swipe(start..., end...)
```

Les versions récentes de XcodeBuildMCP exposent également `drag` et des
références stables d'éléments.

------------------------------------------------------------------------

# 9. IMPORTANT --- Accessibilité de l'application

Pour qu'un agent puisse comprendre l'écran, l'application doit exposer
correctement son arbre d'accessibilité.

Pour SwiftUI, utiliser lorsque nécessaire :

``` swift
.accessibilityIdentifier("settingsButton")
```

Exemple :

``` swift
Button("Settings") {
    ...
}
.accessibilityIdentifier("settingsButton")
```

L'agent pourra alors viser un identifiant stable plutôt qu'une position
à l'écran.

Recommandation :

> Toute commande importante que l'agent doit manipuler pendant les tests
> doit avoir un label ou un `accessibilityIdentifier` stable.

Cela améliore à la fois :

-   XCUITest ;
-   l'automatisation par agent ;
-   la fiabilité des tests ;
-   l'accessibilité de l'app.

------------------------------------------------------------------------

# 10. Problème actuel : impossible de tap / swipe

Procédure de diagnostic :

### Étape A --- vérifier les outils disponibles

``` bash
xcodebuildmcp tools
```

Chercher les outils d'automatisation UI.

### Étape B --- vérifier la configuration

Vérifier :

``` text
.xcodebuildmcp/config.yaml
```

et notamment :

``` yaml
enabledWorkflows:
  - simulator
  - ui-automation
```

### Étape C --- redémarrer le MCP / agent

Une modification de configuration ne garantit pas que le client courant
recharge automatiquement sa liste d'outils.

### Étape D --- tester

Lancer l'app, puis demander successivement :

``` text
snapshot/describe UI
screenshot
tap sur un bouton identifiable
snapshot UI
swipe/gesture
screenshot
```

Si `describe_ui` fonctionne mais pas `tap`, relever l'erreur exacte
plutôt que de contourner immédiatement le problème.

------------------------------------------------------------------------

# 11. Problème du clavier iOS qui ne s'affiche pas

C'est très probablement **un problème de configuration du Simulator**,
pas nécessairement un bug de l'application.

Apple Simulator distingue :

1.  le **clavier hardware** : le clavier physique du Mac est présenté à
    iOS comme un clavier externe ;
2.  le **software keyboard** : le vrai clavier tactile affiché à
    l'écran.

Dans Simulator, regarder le menu :

``` text
I/O -> Keyboard
```

Les options historiques/documentées sont notamment :

``` text
Connect Hardware Keyboard
Toggle Software Keyboard
```

Lorsque le clavier hardware est connecté, iOS peut se comporter comme un
vrai iPhone auquel un clavier externe est relié. Dans ce cas, le clavier
tactile peut ne pas apparaître automatiquement.

C'est probablement ce qui est observé.

------------------------------------------------------------------------

# 12. Configuration recommandée pour tester un clavier iOS

Pour tester **le comportement réel du clavier logiciel** :

``` text
Simulator
-> I/O
-> Keyboard
-> Connect Hardware Keyboard : désactivé
```

Puis toucher un champ texte.

Si nécessaire :

``` text
I/O
-> Keyboard
-> Toggle Software Keyboard
```

Le raccourci généralement associé au toggle du software keyboard est :

``` text
Command + K
```

et celui de la connexion du hardware keyboard :

``` text
Shift + Command + K
```

Les menus du Simulator restent la référence car les
raccourcis/présentations peuvent évoluer selon Xcode.

Apple documente le principe : `Connect Hardware Keyboard` fait utiliser
le clavier du Mac comme clavier externe simulé, tandis que
`Toggle Software Keyboard` contrôle l'affichage du clavier à l'écran.

------------------------------------------------------------------------

# 13. Cas particulier important si l'application EST un clavier iOS

Si le projet testé contient une **Keyboard Extension**, il faut aller
plus loin qu'un simple `type_text`.

L'objectif est alors de tester **le clavier logiciel lui-même**.

Le scénario doit ressembler à un vrai usage :

``` text
1. installer l'application dans le Simulator
2. configurer/activer la Keyboard Extension dans iOS Settings si nécessaire
3. ouvrir une app contenant un champ texte
4. s'assurer que le hardware keyboard simulé ne masque pas le software keyboard
5. donner le focus au champ
6. faire apparaître le clavier logiciel
7. sélectionner le clavier custom si nécessaire
8. interagir avec le clavier par tap/gesture
9. vérifier le texte inséré
```

**Ne pas remplacer ce test par `type_text`.**

`type_text` est très utile pour remplir rapidement un champ, mais si
l'objet du test est précisément une extension de clavier, il
contournerait une partie du comportement que l'on cherche à valider.

------------------------------------------------------------------------

# 14. L'agent peut également manipuler l'app Réglages

Pour des scénarios nécessitant une configuration système --- par exemple
activer une extension de clavier --- l'automatisation UI/XCUITest peut
naviguer dans d'autres applications du Simulator.

Il faut néanmoins considérer les réglages système comme plus fragiles
que l'UI de notre propre application : les labels et la structure
peuvent évoluer entre versions d'iOS.

L'agent doit donc :

``` text
describe_ui
-> chercher le label
-> tap
-> describe_ui
-> continuer
```

et non mémoriser une série de coordonnées fixes.

------------------------------------------------------------------------

# 15. Boucle de travail recommandée pour l'agent

Pour chaque tâche iOS :

``` text
1. Vérifier le contexte XcodeBuildMCP/session.
2. Vérifier projet/workspace + scheme + simulator.
3. Build + run.
4. Vérifier que l'app est effectivement lancée.
5. snapshot_ui / describe_ui.
6. Identifier l'action à effectuer.
7. tap / gesture / swipe / type_text.
8. attendre le changement d'état.
9. snapshot_ui et/ou screenshot.
10. en cas d'échec, récupérer les logs.
11. modifier le code.
12. rebuild + run.
13. répéter jusqu'à validation.
```

Il faut éviter de déclarer une fonctionnalité « terminée » uniquement
parce que le code compile.

Pour une modification UI, la validation minimale doit être :

``` text
BUILD OK
+
APP LAUNCHED
+
SCENARIO EXECUTED
+
EXPECTED UI OBSERVED
```

------------------------------------------------------------------------

# 16. Utiliser les screenshots comme preuve, pas comme unique moyen de contrôle

Un screenshot est excellent pour :

-   vérifier visuellement le résultat ;
-   détecter un problème de layout ;
-   conserver une preuve ;
-   permettre au modèle vision de comprendre une anomalie.

Mais pour **agir**, préférer :

``` text
accessibility tree -> element -> action
```

plutôt que :

``` text
screenshot -> estimation de coordonnées -> clic
```

Les coordonnées restent un fallback utile pour les éléments qui ne sont
pas exposés correctement à l'accessibilité.

------------------------------------------------------------------------

# 17. Logs

Lorsqu'une action provoque un comportement inattendu :

``` text
start log capture
-> reproduire le problème
-> stop log capture
-> analyser
```

XcodeBuildMCP sait capturer les logs du simulateur/de l'application.

L'agent doit conserver au minimum :

-   erreur de build ;
-   crash ;
-   exception ;
-   logs applicatifs pertinents ;
-   screenshot de l'état final ;
-   état UI/accessibility si une interaction échoue.

------------------------------------------------------------------------

# 18. Alternative : ios-simulator-mcp

Il existe aussi :

https://github.com/joshuayoes/ios-simulator-mcp

Ce MCP expose explicitement :

``` text
ui_describe_all
ui_tap
ui_type
ui_swipe
```

Il peut être intéressant si l'on veut uniquement une petite couche de
contrôle du Simulator.

Cependant, **XcodeBuildMCP est recommandé en premier choix** ici parce
qu'il regroupe dans la même interface :

``` text
build + run + simulator + UI + logs + debugging
```

et qu'il est aujourd'hui directement utilisé/recommandé dans des
workflows d'agents iOS, y compris dans le dépôt de plugins OpenAI.

------------------------------------------------------------------------

# 19. Autres alternatives

Il existe d'autres couches d'automatisation iOS :

-   **XCUITest / XCUIAutomation** --- solution Apple native pour les
    tests UI ;
-   **Maestro** --- automatisation UI déclarative ;
-   **Appium** --- framework d'automatisation multi-plateforme ;
-   **IDB** --- outils d'automatisation iOS historiquement développés
    par Meta.

Elles sont pertinentes dans certains environnements de test.

Pour un **agent de développement autonome local**, elles ajoutent
toutefois souvent une couche supplémentaire. Commencer avec
XcodeBuildMCP avant d'empiler plusieurs systèmes.

------------------------------------------------------------------------

# 20. Ne pas confondre `simctl` et automatisation UI

`xcrun simctl` reste indispensable et permet notamment :

``` bash
xcrun simctl list devices
xcrun simctl boot <UDID>
xcrun simctl shutdown <UDID>
xcrun simctl install <UDID> App.app
xcrun simctl launch <UDID> com.example.app
xcrun simctl io <UDID> screenshot screenshot.png
```

Mais si l'agent dit :

> « `simctl` ne propose pas de commande tap/swipe donc je ne peux pas
> naviguer »

la conclusion est incorrecte.

La bonne conclusion est :

> « Il me manque une couche d'automatisation UI ; je dois utiliser
> XcodeBuildMCP/XCUIAutomation ou une solution équivalente. »

------------------------------------------------------------------------

# 21. Checklist d'installation à exécuter maintenant

-   [ ] Vérifier `xcode-select -p`.
-   [ ] Vérifier `xcodebuild -version`.
-   [ ] Vérifier `xcrun simctl list devices`.
-   [ ] Vérifier le runtime iOS utilisé.
-   [ ] Vérifier que l'application compile pour Simulator.
-   [ ] Installer/mettre à jour XcodeBuildMCP.
-   [ ] Exécuter `xcodebuildmcp --help`.
-   [ ] Exécuter `xcodebuildmcp tools`.
-   [ ] Connecter XcodeBuildMCP au client IA.
-   [ ] Activer `simulator`.
-   [ ] Activer **`ui-automation`**.
-   [ ] Activer `debugging` si souhaité.
-   [ ] Redémarrer/recharger le client MCP.
-   [ ] Configurer les session defaults du projet.
-   [ ] Build + run.
-   [ ] Faire `describe_ui`/`snapshot_ui`.
-   [ ] Tester un **tap**.
-   [ ] Tester un **swipe/gesture**.
-   [ ] Tester un screenshot.
-   [ ] Tester une saisie texte.
-   [ ] Vérifier `I/O -> Keyboard -> Connect Hardware Keyboard`.
-   [ ] Pour tester le clavier logiciel : déconnecter le hardware
    keyboard.
-   [ ] Faire apparaître le software keyboard.
-   [ ] Si le projet contient une Keyboard Extension, tester le clavier
    par interactions UI réelles et pas uniquement via `type_text`.
-   [ ] Ajouter des `accessibilityIdentifier` aux éléments importants
    qui sont difficiles à cibler.
-   [ ] Valider une boucle complète build -\> launch -\> interaction -\>
    observation -\> logs.

------------------------------------------------------------------------

# 22. Prompt/instruction permanente à donner à l'agent

L'agent devrait adopter les règles suivantes :

``` text
Pour tout travail iOS, utilise XcodeBuildMCP comme interface privilégiée
vers Xcode et iOS Simulator.

Ne conclus jamais qu'une interaction UI est impossible simplement parce que
simctl ne possède pas de commande tap/swipe.

Avant une interaction, inspecte l'UI avec snapshot_ui/describe_ui.
Préfère toujours accessibility identifier ou label aux coordonnées.

Pour naviguer :
- tap pour les boutons/éléments ;
- gesture/swipe/drag pour les gestes ;
- type_text uniquement lorsque le but est de saisir directement du texte ;
- screenshot pour la validation visuelle.

Après chaque changement d'écran important, réinspecte l'UI.

Si les outils tap/swipe/type_text ne sont pas disponibles, vérifie que le
workflow ui-automation de XcodeBuildMCP est activé et recharge le MCP.

Pour tester le clavier logiciel iOS, vérifie l'état de
Simulator > I/O > Keyboard > Connect Hardware Keyboard.
Un hardware keyboard simulé peut empêcher le clavier logiciel de se présenter
comme attendu.

Si le produit testé est lui-même une Keyboard Extension, ne considère pas
type_text comme un test du clavier. Fais apparaître le vrai software keyboard,
sélectionne l'extension et interagis avec ses contrôles.

Ne considère pas une modification UI comme validée uniquement parce qu'elle
compile. Exécute le scénario utilisateur dans Simulator et vérifie le résultat
avec l'arbre UI et/ou un screenshot.

En cas d'échec :
1. capture l'état UI ;
2. prends un screenshot ;
3. récupère les logs ;
4. explique précisément l'étape qui échoue ;
5. corrige ;
6. rebuild et reteste.
```

------------------------------------------------------------------------

# 23. Ordre d'action conseillé à l'agent qui reçoit ce document

**Ne réinstalle pas tout aveuglément.**

Commence par auditer l'installation existante :

``` text
A. Xcode
B. runtimes Simulator
C. projet/scheme
D. XcodeBuildMCP présent ou absent
E. version de XcodeBuildMCP
F. workflows activés
G. outils MCP réellement visibles
H. état hardware/software keyboard
```

Ensuite, corrige uniquement les éléments manquants.

La première hypothèse à tester pour le problème actuel de tap/swipe est
:

> XcodeBuildMCP absent, non connecté, trop ancien, ou workflow
> `ui-automation` non activé.

La première hypothèse à tester pour le clavier qui ne s'affiche pas est
:

> `Connect Hardware Keyboard` est actif dans Simulator, ou le software
> keyboard a été masqué/togglé.

------------------------------------------------------------------------

# 24. Critère final de réussite

L'environnement n'est considéré correctement configuré que lorsque
l'agent est capable, **sans intervention humaine**, de réaliser un
scénario comparable à :

``` text
1. compiler l'app ;
2. démarrer le bon simulateur ;
3. lancer l'app ;
4. inspecter l'écran ;
5. identifier un bouton ;
6. taper dessus ;
7. vérifier le nouvel écran ;
8. faire un swipe/scroll ;
9. toucher un champ texte ;
10. faire apparaître le clavier logiciel lorsque le scénario l'exige ;
11. saisir/interagir ;
12. prendre un screenshot ;
13. récupérer les logs ;
14. signaler PASS/FAIL avec la cause précise.
```

Tant que `tap` et `swipe` sont impossibles, **la configuration agentique
du Simulator est incomplète**, même si build et launch fonctionnent.

------------------------------------------------------------------------

# Sources principales

-   Apple --- Simulator interaction / hardware & software keyboard:\
    https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/iOS_Simulator_Guide/InteractingwithiOSandwatchOS/InteractingwithiOSandwatchOS.html

-   XcodeBuildMCP --- dépôt principal :\
    https://github.com/getsentry/XcodeBuildMCP

-   XcodeBuildMCP --- configuration de référence :\
    https://github.com/getsentry/XcodeBuildMCP/blob/main/config.example.yaml

-   XcodeBuildMCP --- documentation :\
    https://xcodebuildmcp.com/

-   XcodeBuildMCP --- clients MCP :\
    https://xcodebuildmcp.com/docs/clients

-   OpenAI plugins --- skill `ios-debugger-agent`, qui documente
    l'utilisation de XcodeBuildMCP avec `describe_ui`, `tap`,
    `type_text`, `gesture`, screenshots et logs :\
    https://github.com/openai/plugins/blob/main/plugins/build-ios-apps/skills/ios-debugger-agent/SKILL.md

-   XcodeBuildMCP --- skill officiel :\
    https://github.com/getsentry/XcodeBuildMCP/blob/main/skills/xcodebuildmcp/SKILL.md

-   ios-simulator-mcp --- alternative spécialisée Simulator :\
    https://github.com/joshuayoes/ios-simulator-mcp

------------------------------------------------------------------------

## Conclusion

Le Simulator Apple est suffisamment automatisable pour permettre à un
agent de développer et tester une app iOS de manière largement autonome.

Le blocage « pas de tap/swipe » vient vraisemblablement du fait que
l'agent utilise uniquement les outils Apple bas niveau (`xcodebuild` /
`simctl`) ou qu'il dispose de XcodeBuildMCP **sans son workflow
`ui-automation`**.

La configuration cible est :

``` text
Claude Code / Codex / agent local
        +
XcodeBuildMCP
        +
simulator + ui-automation
        +
Apple iOS Simulator
```

Pour le problème de clavier, vérifier en priorité la distinction
**Hardware Keyboard / Software Keyboard** dans
`Simulator > I/O > Keyboard`. Pour une application comportant une
extension de clavier, cette configuration est particulièrement
importante.
