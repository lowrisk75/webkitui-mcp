# Retour de session Lumen / Play Console — corrections

Date : 2026-09-23. Source :
`Lumen for Frigate/docs/qa/webkitui-native-mcp-session-feedback-2026-09-23.md`.
Aucun commit, installation, notarisation ou publication.

## Corrigé, avec test de régression

| Constat du rapport | Cause | Correction | Preuve |
| --- | --- | --- | --- |
| P1 : `targetNotFound(["context_anchor:previous_sibling"])` sur l'onglet Testers, deux fois sans mutation | L'observation ignore un voisin `aria-hidden` ; la résolution de l'action ne l'ignorait pas (et l'inverse pour l'opacité d'un ancêtre) : les deux côtés lisaient deux voisins différents | `isAnchorRendered` dans les helpers d'action, même règle que l'observation, pour `previous_sibling` et `same_row_label` | Test « A previous-sibling anchor resolves past an aria-hidden neighbour… » : échoue sans la correction avec exactement l'erreur du rapport |
| Remédiation illisible `previous_sibling"])` | `toolError` coupait au premier `:` même quand le préfixe n'est pas un code valide | Découpe seulement une paire `code: remédiation` reconnue (`toolErrorFields`) | Test « A colon inside an error message… » |
| P1 : dialogues non exposés hors mode humain, fond `covered` | Fenêtre agent hors écran : la page est `hidden` et `requestAnimationFrame` ne tourne pas ; un dialogue Material attend une frame pour insérer son contenu. De plus la fenêtre n'était placée qu'au premier `observe`/`readText` | Visibilité de la page découplée de l'occlusion de la fenêtre (`_setWindowOcclusionDetectionEnabled:NO`, vérifié avant usage, repli sur l'ancien comportement) ; fenêtre parquée dès l'init | Mesuré avant : `visibility=hidden frames=0`. Après : `visible`, 30 frames. Test « The parked agent window still runs animation frames… » |
| P2 : reload `deadline_reached` journalisé `succeeded` | Le journal ne notait que le transport | Champ optionnel `result_state`, vocabulaire fermé : `deadline_reached`, `process_terminated`, `indeterminate`, `verification_pending`, `verified_by_immediate_reconciliation`, `blank_capture` | Tests du journal |
| P2 : erreurs toutes `tool_error` | Idem | `error_type` = code précis ou identifiant de tête du message (`staleObservation`, `targetNotFound`), jamais le reste | Idem |
| P2 : capture blanche marquée réussie | Pas de contrôle de l'image | `image_uniform` dans `browser_capture` (32×32, tolérance 3/255) ; journal `blank_capture`. L'observation reste l'autorité sur le contenu | Test « A flat capture is flagged… » |

Fuite corrigée au passage : une fenêtre parquée reste retenue par AppKit et garde
le WebView, son process web et son magasin de données. Aucun runtime ne la fermait ;
`isolated deinit` la ferme désormais. Révélé par le test du magasin persistant
(« Data store is in use ») dès que la fenêtre est parquée à l'init.

Autre ajout : le diagnostic opt-in du helper de confirmation
(`WEBKITUI_CONFIRM_KEYBOARD_DIAGNOSTICS=1`) enregistre la source d'une approbation
(`keyboard`, `mouse`, `posted_mouse_pid_N`, `accessibility`).

## API privée

`_setWindowOcclusionDetectionEnabled:` est une SPI WebKit. Distribution prévue :
téléchargement direct notarisé, pas le Mac App Store. L'appel est gardé par
`responds(to:)` ; si WebKit la retire, le runtime reprend l'ancien comportement et
le test de frames échoue, ce qui signale la régression.

## Non traité

- Coordonnées `x=-42`/`x=-54` après reprise : non reproduit.
- `staleObservation` juste après `handoff_resume` : le refus est correct ; une
  indication « transition en cours » reste une amélioration de conception.
- Clarté des confirmations et reprises successives : conception, pas un défaut.
- Validation physique sur Play Console avec l'app installée : à faire après
  réinstallation.

## Deuxième dossier (handoff complet ASC / Reddit)

Source : `Lumen for Frigate/docs/qa/WEBKITUI-MCP-HANDOFF-COMPLET-2026-09-23.md`.

| Constat | Cause | Correction | Preuve |
| --- | --- | --- | --- |
| P1 : App Store Connect → `full_browser_required`, impasse | Règle codée en dur depuis le 2026-08-24 : le cadre `idmsa` « bloqué » était la page masquée (0 frame), pas une limite de WKWebView | Paire ASC → idmsa retirée : la connexion Apple passe par le handoff humain natif. `idmsa` reste restreint (ni lecture, ni capture, ni remplissage par l'agent). Règle Cloudflare WebAuthn conservée | Même URL publique `appstoreconnect.apple.com/login`, sans identifiant : page masquée → spinner seul ; page visible → formulaire Compte Apple complet (captures locales) |
| P1 : remplacement d'un éditeur riche non vide (Reddit) → ancien texte + nouveau | L'éditeur rétablit son curseur à la tâche suivant le focus ; la sélection posée par le script d'armement était perdue | `selectAll` natif de WebKit juste avant `insertText`, dans le même tour | Test avec restauration asynchrone du curseur : `"Old draftFirst paragraph…"` avant, remplacement exact après |
| `preconditionUnsatisfied` sans explication | Nom de cas brut | Remédiations ciblées pour `staleObservation`, `targetNotFound`, `targetNotActionable`, `preconditionUnsatisfied`, `preconditionUnknown` | Test |

Non reproduit :

- Insertion du seul premier paragraphe : WebKit seul crée bien les deux paragraphes ;
  exige l'éditeur Lexical réel.
- Radio Reddit `targetNotActionable` : un radio à input transparent superposé passe ;
  Reddit utilise des composants en shadow DOM. Test gardé comme couverture.
- `read_text` sans le panneau de chat Reddit, contrôles sans rôle ni nom : à
  reproduire avec des shadow roots.
- Capture 2880×2000 tronquée : limite du transport du client, pas du serveur.

## Validation

- `swift-format lint --strict` et `git diff --check` : rc=0.
- État final, debug et release : 5 résumés Swift Testing chacun,
  135 + 190 + 18 + 90 + 56 = 489, plus 13 XCTest, 0 échec. Exclusion :
  `hostExclusiveSession` (broker installé actif). Formatage des tests appliqué
  ensuite (espaces seulement), build des tests rc=0.
- Un passage release antérieur a perdu le résumé du bundle serveur (82 tests sans
  issue, rc=0, aucun rapport de crash). Le bundle seul et les deux passages suivants
  sont propres. Cause non identifiée ; à surveiller.
