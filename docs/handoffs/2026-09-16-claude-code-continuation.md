# Handoff complet — WebKitUI MCP → Claude Code

Date : 2026-09-16. Dépôt : `/Users/kevinnadjarian/GitHub/webkitui-mcp`.
Mission : `10342528-D73D-44AC-9868-B8C6AF5A7E92`.
Ancienne session Claude : `12d0425b-4ef8-4186-9261-746b415a8043`.

## 1. Résumé de reprise

Le travail est **local, non committé, non installé**. Les tâches 1–4 du plan
cross-origin sont implémentées ; la tâche 5 est partiellement mesurée. Le dernier
rapport de validation consigne **493 tests réussis**, lint et diff-check propres.
Ce n'est ni une preuve du comportement du binaire installé, ni une résolution de
la page blanche Apple Contact Us, ni une qualification de checkout/SSO réel.

La prochaine étape est de fermer la preuve manquante sur une iframe
d'authentification restreinte, puis de qualifier un parcours réel avec un binaire
identifié. Commencer par réconcilier le dépôt et inspecter les tests existants ;
ne pas réimplémenter les tâches déjà terminées. Un test local de contrat peut
avancer sans contacter un fournisseur, mais ne remplace pas sa qualification.

La demande courante portait uniquement sur ce handoff. Elle n'autorise pas à
installer, relancer, committer ou publier. Confirmer le périmètre de reprise avec
le prochain message de Kevin.

## 2. Autorité et garde-fous

- Préserver **toutes** les modifications suivies et non suivies. Aucun reset,
  clean, stash, réécriture de l'historique ou suppression pour faciliter la reprise.
- Pas de commit, push, installation, remplacement du binaire, redémarrage du
  broker, signature/notarisation, upload ou publication sans GO explicite.
- Pas d'envoi à Apple, de formulaire, d'achat ni d'autre mutation de compte implicite.
- Ne pas modifier Velya/Veyla : cette branche de conversation était une erreur
  de discussion, explicitement retirée par Kevin. Le périmètre est WebKitUI MCP.
- Répondre en français, brièvement, avec preuves et limites séparées.
- Les faits historiques sur des processus, sessions ou versions installées sont
  des pistes à vérifier, pas un état actuel garanti.
- L'instruction AGENTS fournie par Kevin ne demande pas un appel RAG systématique.
  `throttle_global_context`, limite 6, seulement si la réutilisation interprojets
  ou le handoff change matériellement le travail. Aucun résultat n'autorise une mutation.

## 3. Snapshot Git frais à la rédaction

Branche `main`, HEAD `0979da728d04bc973fa4f351f6a38d5f77ff98fd`.
Diff suivi : **16 fichiers, 3816 insertions, 226 suppressions**. Ces chiffres
excluent les fichiers non suivis et le présent handoff, ajouté ensuite.

```text
 M Package.swift
 M README.md
 M Sources/WebKitUIMCPConfirm/main.swift
 M Sources/WebKitUIMCPCore/LocatorRecipe.swift
 M Sources/WebKitUIMCPRuntime/CanonicalPageState.swift
 M Sources/WebKitUIMCPRuntime/WebKitRuntime.swift
 M Sources/WebKitUIMCPRuntime/WebKitSessionRegistry.swift
 M Sources/WebKitUIMCPRuntime/WebKitTransactionCoordinator.swift
 M Sources/WebKitUIMCPServer/MCPServer.swift
 M Support/AquaApp/en.lproj/Localizable.strings
 M Support/AquaApp/fr.lproj/Localizable.strings
 M Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift
 M Tests/WebKitUIMCPServerTests/CapabilityClaimsCoherenceTests.swift
 M Tests/WebKitUIMCPServerTests/MCPServerTests.swift
 M docs/architecture/native-runtime-and-mcp.md
 M docs/superpowers/plans/README.md
?? Tests/WebKitUIMCPAdversarialTests/
?? docs/research/2026-09-09-adversarial-corpus-measurement.md
?? docs/research/2026-09-16-cross-origin-frame-boundary-measurement.md
?? docs/superpowers/plans/2026-09-15-cross-origin-frames.md
```

Le travail accumulé dépasse le seul cross-origin : corpus adversarial, corrections
de confidentialité et de confirmation, viewport/historique et refus de permissions.
Inspecter le diff complet avant de découper d'éventuels commits. Le plan Reach
historique ne constitue pas à lui seul un inventaire à jour des tâches terminées.

Derniers commits :

```text
0979da7 fix: withhold what is chosen in a sensitive select, not just what is typed
790bb80 docs: plan the sensitive select that still names what is chosen in it
c6ca806 feat: publish the option labels a select will actually accept
b2db612 docs: plan the missing half of select_option
```

La tâche 9 du handoff initial est donc déjà dans HEAD : `selectedOption` d'un
select sensible ne fuit plus dans l'observation ni l'état canonique. Ne pas la
repartir de zéro. Les options sont optionnelles/absentes lorsqu'il n'y a rien à
publier ; remettre des tableaux vides partout casserait le budget wire existant.

## 4. Documents à lire, dans cet ordre

1. `docs/superpowers/plans/2026-09-15-cross-origin-frames.md` — contrat et tâches.
2. `docs/research/2026-09-16-cross-origin-frame-boundary-measurement.md` — preuves et limites récentes.
3. `docs/research/2026-09-09-adversarial-corpus-measurement.md` — AC-01 à AC-04.
4. `docs/superpowers/plans/README.md` — axes Safety / Reach / Proof.
5. `docs/superpowers/plans/2026-09-09-reach-gaps.md` et `2026-09-09-adversarial-corpus.md`.
6. `docs/architecture/native-runtime-and-mcp.md`, `README.md`, puis code et tests du diff.

Les documents de mesure et le nouveau plan sont actuellement **non suivis** :
ne pas les perdre en transférant uniquement un `git diff`.

## 5. Cross-origin : implémentation et invariants à conserver

### Tâches 1–2 : identité et observation

- Enregistrement document-start dans le `WKContentWorld` isolé, via le véritable
  `WKScriptMessage.frameInfo`. Conservation du `WKFrameInfo` exact et d'une
  capacité opaque privée ; registre borné à 32, débordement explicite.
- Le collecteur principal parcourt ses descendants same-origin ; collecte
  séparée des frames enregistrées qu'il ne peut lire, avec déduplication.
- Filtres, pagination et budget d'éléments globaux après fusion. Évaluation
  individuelle bornée à deux secondes ; frame illisible = observation incomplète,
  jamais preuve d'absence d'un contrôle.
- Provenance `THIRD_PARTY_EMBED`, origine nettoyée sans chemin/query/fragment,
  `frameIsMain=false`, coordonnées `frame_viewport`.
- Capacités natives jamais encodées. Valeurs sensibles, cartes, OTP et états
  sensibles retirés ; un contrôle sensible reste identifiable comme contrôle.

### Tâche 3 : résolution après confirmation

- `frameRegistrationGeneration` et navigation enfant invalident l'observation
  entière : pas de stable ID public permettant d'expirer sûrement un sous-ensemble.
- `FrameActionContext` lie capacité exacte, documentID, observationID et origine.
- `frameActionGuardSource` vérifie capacité et `location.origin` dans le monde
  isolé avant résolution/action. Le site ne fournit pas cette autorité.
- Recipe riche `resolutionRecipe` privée ; recipe publique minimale. Préflight
  et dispatch revérifient sémantique, unicité, état et géométrie locale.
- Stale/mismatch : pas de dispatch. Remplacement de nœud : récupération sémantique
  mesurée, sans détour par l'ordre des iframes ou leur URL.

### Tâche 4 : modes d'action bornés et vérité du reçu

- Hover/select enfant : JavaScript explicitement **non trusted**.
- PressKey/fill non sensibles : nativeAppKit, confirmation native contrôlée par
  le serveur, reçu lié à l'enfant exact et `isTrusted` requis.
- Jetons de geste armés liés à capacité/origine ; contrôle du type d'événement,
  identité physique, WKFrameInfo non principal et origine native.
- Reçu absent/non trusted : `nativeGestureReceiptUnavailable`, résultat inconnu,
  réconciliation, **aucun replay automatique**.
- Click/pointer, submit, upload/download cross-origin : refus avant confirmation
  `cross_origin_native_geometry_unavailable`, `dispatched=false`, route handoff.
  Ne pas inventer une transformation de coordonnées ni substituer un clic JS.
- Confirmation affiche l'origine enfant et le mode réel. Autorité de capacité,
  origine attendue de transaction et `approvedSubmissionOrigin` sont liées à
  l'enfant, pas arbitrairement au document principal.
- État canonique : namespace frame `embedded` contre `main` ; resolver après
  select ne réclame plus l'ancienne sélection qu'il vient de modifier.

### Correctif important trouvé par les tests MCP

Une recipe publique réduite au tag rendait deux `<input>` enfants identiques
pour la vérification, malgré des gestes correctement attribués. Correction :

- `LocatorRecipe.opaqueSemanticIdentity` optionnel.
- HMAC SHA256 sur capacité + identité de recipe privée, clé privée
  `frameSemanticKey` 256 bits renouvelée à la navigation principale.
- Identité opaque stable pour la cible exacte du document, pas un hash public
  devinable des labels. Aucune recipe riche tierce exportée.
- MCP retire `locatorRecipe` de l'observation wire ; les représentations internes
  peuvent garder le tag et cette identité opaque.
- Précondition d'un input enfant initialement vide : présence `@tag`, pas un
  `@value` inexistant. Postcondition de fill exacte toujours exigée.

`WebKitFrameActionMode` expose les tentatives admissibles :
`hover_javascript`, `select_option_javascript`, `press_key_native_appkit`,
`fill_native_appkit`. Champ complet `frameActionModes`, compact `frame_action_modes`.
Nil sur main ; liste vide si sensible, disabled, invisible ou bbox nulle.
Ce n'est pas une promesse de dispatch : les contrôles live peuvent encore refuser.
`actionable=false` reste le refus de géométrie pointer, distinct de ces modes.

`WebKitSessionRegistry` dispose d'une factory runtime interne pour les fixtures
déterministes. Le constructeur public conserve le runtime persistant protégé ;
ne pas transformer ce seam de test en contournement de production.

## 6. Corpus et tests à connaître

`Tests/WebKitUIMCPAdversarialTests/` contient le harness et cinq suites :
ConfirmationForgery, DestinationTruth, HiddenInstruction, ReceiptLeak et
CrossOriginFrame. Le dernier fichier ajoute trois tests déterministes :

1. Texte hostile attribué au tiers, tentatives page-world de forger identité/reçu,
   recherche de canaris dans les octets JSON observation et état canonique.
2. Origines imbriquées collectées une fois avec leur origine réelle.
3. Deux URLs enfant identiques conservent deux identités opaques distinctes ;
   aucune capacité ou chemin privé exporté.

Les tests runtime/MCP supplémentaires couvrent navigation enfant stale,
remplacement, doublons, budget/pagination, overflow/révocation, hover/select
non trusted, key/fill avec reçu trusted, reçu manquant et refus pointer avant
confirmation. Points d'entrée : `--filter crossOrigin` et
`--filter CrossOriginFrameCorpusTests`.

Trouvailles antérieures : AC-01 destination `formaction` mutée avant confirmation,
AC-02 noms longs bornés incohérents, AC-03 valeurs de query visibles : corrigées
localement. **AC-04 reste une décision produit ouverte/acceptée pour la mesure** :
fragment de l'URL principale visible. L'absence de fragment dans une origine
enfant ne ferme pas AC-04. Le corpus ne prouve pas la résistance d'un modèle
autonome à l'injection ; il mesure la frontière observable du produit.

## 7. Validation : niveau exact de preuve

Le rapport local du 2026-09-16 consigne la suite complète, rc=0 :

| Cible | Tests |
| --- | ---: |
| Server | 131 |
| Runtime | 185 |
| Licensing | 18 |
| Core | 90 |
| Adversarial | 56 |
| Confirm-policy XCTest | 13 |
| **Total** | **493** |

Lint strict rc=0 ; `git diff --check` rc=0. Les exécutions ciblées cross-origin
et les trois tests du nouveau corpus étaient également réussies.
`hostExclusiveSession` était explicitement exclu : ne pas annoncer une suite
sans exclusions. Pas de chemin de log brut complet garanti dans ce handoff.

Pendant la rédaction du présent transfert, Git, docs, espace disque et hash du
rapport externe ont été relus ; **la suite de tests n'a pas été relancée**.
Le diff-check a été exécuté de nouveau. Les 493 sont la preuve consignée de la
validation précédente, pas une nouvelle exécution imputable à ce handoff.

Commande de reproduction utilisée (vérifier le montage et les répertoires avant) :

```sh
cd /Users/kevinnadjarian/GitHub/webkitui-mcp
env TMPDIR=/Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp-cross-origin-task2/tmp \
  CLANG_MODULE_CACHE_PATH=/Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp-cross-origin-task2/clang-cache \
  swift test \
  --scratch-path /Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp-cross-origin-task2/swiftpm \
  --arch arm64 --no-parallel --skip hostExclusiveSession
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
git diff --check
```

Warnings historiques non corrigés : `String(cString: buffer)` déprécié dans
WebKitSessionRegistry ; certains tests download émettent des diagnostics sandbox
sans échouer. Ne pas assimiler cela à une causalité du bug Apple Contact Us.

## 8. Rapport Apple Contact Us : incident séparé, toujours non résolu

Fichiers encore présents à la rédaction :

- `/private/tmp/halte-webkitui-contact-retry-2026-09-15.md`
- `/private/tmp/claude-501/-Users-kevinnadjarian-GitHub-webkitui-mcp/12d0425b-4ef8-4186-9261-746b415a8043/scratchpad/feedback-halte-apple-contact-webkitui-2026-09-15.md`

SHA256 du premier, **revérifié à la rédaction** :
`735cdac29814b2863a6b1249749557956979e6f219b058c876623019b9b76958`.

Selon le retour utilisateur : WebKitUI **0.6.8 build 608**, Apple Developer
authentifié fonctionne (450 éléments), Apple Contact Us reste vide (0 élément,
aucun texte, capture blanche). Erreurs WebContent/sandbox et connexions
réinitialisées, sans causalité démontrée. Aucun formulaire/email envoyé,
dépôt Halte non modifié, session de test libérée selon ce compte rendu.
Ce n'est pas une inspection fraîche du binaire installé. Lire le rapport avant
de proposer un diagnostic ; ne pas attribuer automatiquement le blanc aux iframes.

## 9. Ce qui reste, par priorité

1. **Preuve Task 5 locale fermée le 2026-09-16 (reprise Claude Code, voir §12)** :
   le chemin restricted-auth enfant est testé hors ligne
   (`restrictedAuthenticationChildFrameHandoffAndResume`). Reste ouvert : une vraie
   iframe Apple ID, ses contrôles rendus et tout parcours fournisseur.
2. **Qualifier le runtime réel avec une version identifiable** : après GO adapté
   pour build/install/relaunch, relever artefact/hash/version/processus, utiliser
   une session dédiée et rejouer le cas Apple Contact Us avec un témoin fonctionnel.
   Aucun envoi/formulaire nécessaire pour mesurer le rendu.
3. **Revoir le diff accumulé et préparer la livraison** : autorisation distincte
   avant commits, packaging signé, installation ou publication.

Limites assumées, pas tâches implicitement promises : pas de native mouse transform
cross-origin, pas de preuve checkout hébergé/CAPTCHA/SSO/backend commit. Le plan
global conserve également les preuves provider avec read-back indépendant,
authentification physique Mac et canari payant jusqu'au remboursement/révocation.
HTTP status main-frame, journal console et contacted-host list restent différés
dans l'index. Ne pas élargir automatiquement cette reprise à tous ces chantiers.

## 10. Risque environnemental immédiat

Disque interne à la rédaction : **1,7 Gio disponibles**, capacité affichée 100 %.
DeveloperStorage : **1,6 Tio disponibles**. Le scratch externe évite les builds
par défaut qui ont déjà rencontré le manque d'espace. Ne supprimer ni caches,
artefacts, ni données utilisateur sans autorisation ciblée. Si le volume externe
est absent, arrêter avant un gros build sur le disque interne.

## 11. Première séquence recommandée à Claude

```sh
cd /Users/kevinnadjarian/GitHub/webkitui-mcp
pwd
git status --short --branch
git rev-parse HEAD
git diff --stat
git diff --check
rg --files -g AGENTS.md -g CLAUDE.md
df -h /System/Volumes/Data /Volumes/DeveloperStorage
```

Lire les instructions effectivement présentes, puis les documents de §4.
Comparer ce snapshot au réel, préserver toute évolution concurrente. Rapporter
ce qui est déjà prouvé et proposer la prochaine vérification bornée. Si Kevin
autorise la continuation locale, fermer d'abord le contrat restricted-auth
testable sans fournisseur ; si une preuve réelle exige installation, session
authentifiée ou action externe, demander précisément cette autorisation.

Ne jamais transformer « handoff disponible » en « implémentation livrée ».

## 12. Reprise Claude Code — 2026-09-16 (mission 10342528)

Périmètre exécuté : validation locale de l'iframe d'authentification restreinte.
Aucun commit, push, installation, relance de broker, signature ni publication.
HEAD inchangé `0979da7` ; tout le worktree précédent est préservé.

Changements de cette reprise :

- `Tests/WebKitUIMCPRuntimeTests/WebKitRuntimeTests.swift` : nouveau test
  `restrictedAuthenticationChildFrameHandoffAndResume`. Un parent `account.test`
  embarque `idmsa.apple.com:<port>` ; le `PinnedSOCKSProxy` résout ce nom vers
  loopback, donc le vrai hostname atteint la politique de navigation sans qu'aucun
  octet ne sorte de la machine. Vérifié : refus explicite
  `authenticationOriginRequiresHuman(<origine enfant>)` sur observe/readText/capture/
  perform, classification `humanHandoffRequired`, handoff humain et étape terminée,
  reprise refusée tant que la frame existe, reprise acceptée après navigation
  principale, observation main-frame seule, aucun canari de query dans résultat,
  statut ou observation.
- Aucune source de production modifiée : le chemin enfant existant se comporte
  comme le contrat. Le seul ajustement du test : WebKit applique le préchargement
  HSTS d'apple.com et reclasse la frame en `https` avant la décision de politique ;
  l'origine refusée est donc `https://idmsa.apple.com:<port>`.
- Docs : `docs/research/2026-09-16-cross-origin-frame-boundary-measurement.md`
  (section « Follow-up validation ») et statut Task 5 du plan cross-origin.

Limite constatée, non corrigée (décision produit) : la restriction enfant n'est levée
que par une navigation principale. Une page qui retire l'iframe sans naviguer laisse
l'agent refusé jusqu'à ce que l'humain navigue ou recharge. Fail-closed, à documenter.

Environnement : disque interne tombé à 0 en début de session ; avec accord de Kevin,
suppression de `~/Library/Caches/LorisLabsBuild` (DerivedData Éclair du 8 sept.) et
`~/Library/Caches/go-build` (≈4,4 Go) → ≈14,5 Go libres. Rien d'autre supprimé.
Mémoire hôte saturée (16 Go, plusieurs sessions agent) : builds en `-j 1`, `nice`.

Validation de cette reprise (scratch DeveloperStorage) :

- Test ciblé : rc=0, 1/1 (4,3 s).
- `xcrun swift-format lint --strict --recursive Sources Tests Package.swift` : rc=0.
- `git diff --check` : rc=0.
- Suite complète `--skip hostExclusiveSession` : FULL_SUITE_RESULT

Prochaine étape : inchangée, §9 points 2 et 3 (binaire identifiable, Apple Contact
Us, revue du diff et livraison), chacun sous autorisation distincte.
