# Reprise Codex — mission 10342528

Date : 2026-09-21. Mission : `10342528-D73D-44AC-9868-B8C6AF5A7E92`.
Reprise de Claude Code `12d0425b-4ef8-4186-9261-746b415a8043`.

## État réconcilié

- `main`, HEAD `f7036db`. Arbre propre à l'arrivée ; le code du handoff du
  16 septembre est déjà committé. Ne pas reprendre son état historique comme
  inventaire actuel de modifications non committées.
- App installée : 0.6.9 (609), provenance `9977a02`, arbre déclaré clean.
  Signature `codesign --verify --deep --strict` valide hors sandbox.
  Le premier refus de signature dans le sandbox n'était pas une preuve de
  corruption ; la vérification hors sandbox a réussi.
- Les six exécutables installés correspondent aux sections machine du build
  `.build/release` préexistant **et du build de production fraîchement reconstruit**
  sur le scratch externe. Cela ne suffit pas à valider la gate complète.
- Au premier contrôle, le verrou hôte était tenu par le broker installé, PID 1024.
  Ce n'était plus le PID 15326 historique. La fermeture a ensuite été autorisée
  explicitement par Kevin et vérifiée ; voir le suivi ci-dessous.
- Deux documents ajoutés dans cette reprise : ce handoff et le
  [diagnostic Volvo](../diagnostics/2026-09-21-volvo-rendering-and-panel-postcondition.md).
  Aucun changement du runtime, commit, installation ou publication.

## Validation fraîche

- Lint Swift strict et `git diff --check` : rc=0.
- `python3 scripts/test-release-gates.py` : rc=0 ; exécutables obsolètes et
  manifeste obsolète rejetés, variantes de signature acceptées, erreur de probe
  conservée et extraction de localisation vérifiée.
- Syntaxe Node du vérificateur et syntaxe zsh de la gate : rc=0.
- Suites debug **et** release : rc=0, cinq résumés Swift Testing par configuration,
  131 serveur + 186 runtime + 18 licensing + 90 core + 56 adversarial,
  plus 13 XCTest = **494 par configuration**, sans échec.
- Exclusion explicite : `hostExclusiveSession`, conformément à la gate existante
  lorsqu'un broker installé détient l'hôte. Le contrôle live à deux clients a
  ensuite été exécuté séparément, après autorisation de fermeture de session.
- Scratch externe :
  `/Volumes/DeveloperStorage/BuildScratch/Auto/webkitui-mcp-cross-origin-task2/swiftpm`.
  Options : `--arch arm64 -j 1 --no-parallel --skip hostExclusiveSession`.
  Le script temporaire reprend le garde-fou `run_tests` de la gate : chaque bundle
  doit produire son résumé ; un simple exit 0 ne suffit pas.
- Log brut : `/private/tmp/webkitui-10342528-validation.log`.
- Build production après les tests : `swift build -c release --arch arm64 -j 1`
  avec le même scratch externe, rc=0. Six comparaisons `__TEXT __text` identiques
  aux exécutables installés. Logs :
  `/private/tmp/webkitui-10342528-production-build.log` et
  `/private/tmp/webkitui-10342528-machine-code.log`.
  Comparer après ce build de production, comme le fait la gate : les exécutables
  issus de `swift test -c release` différaient avant cette étape et ne constituaient
  pas une preuve d'installation obsolète.

## Gate installée toujours ouverte

Le bloc exact de vérification du manifeste sort en **rc=1** :
`installed app source manifest differs from current release inputs`.
Log : `/private/tmp/webkitui-10342528-provenance.log`.

Le hash du manifeste installé correspond à son plist de provenance. Comparer
chaque entrée aux fichiers actuels donne un seul écart :
`scripts/verify-installed-native.mjs`, modifié par `f7036db` après l'installation
de `9977a02`. Le diff entre ces deux commits contient uniquement ses 13 lignes.
Ne pas affaiblir le contrôle ni éditer le manifeste scellé pour le rendre vert.

La gate n'est donc **pas seulement bloquée par une autre session**. Libérer l'hôte
ne ferme pas l'écart de provenance. Une livraison ultérieure doit reconstruire
un paquet à provenance cohérente, puis vérifier son installation, avec l'hôte
disponible et les autorisations applicables. Ne pas interrompre la session Volvo
pour cela par défaut. Le vérificateur live ouvre puis ferme la session default.

## Suivi : fermeture autorisée et contrôle live

Kevin a explicitement autorisé la fermeture de la session pour la vérification.
Le statut a confirmé le même identifiant de session, encore sous contrôle humain
et détenu par un autre client. Première fermeture refusée `session_in_use`, puis
transfert `client_handoff` approuvé dans la confirmation native.

Attention au contrat installé : `close` retourne `closed=true` **avec**
`browser_preserved=true`. Le premier vérificateur à deux clients sortait rc=0 et
annonçait `hostReleased=true`, alors que le verrou et le handoff existaient encore.
Ce champ du script Node n'est donc pas une preuve suffisante de libération ;
la boucle `lsof` de la gate shell reste nécessaire. Le broker durable conserve
le navigateur, et le délai de libération de 20 secondes ne démarre pas tant qu'un
handoff ou une capacité de reprise le protège.

La commande native « Libérer le bail d'hôte » a été ouverte pour la fermeture
autorisée. Le contrôle automatique du clic de confirmation a expiré ; le dialogue
n'était plus présent au contrôle suivant, sans nouvelle tentative. État ensuite
vérifié indépendamment : `no_active_session`, `control_available=true` et verrou
libre. Ne pas attribuer la confirmation à une action automatisée réussie faute
de reçu ; la fermeture effective est prouvée par les contrôles d'état.

Le vérificateur a été relancé depuis cet état libre : 0.6.9, 2 clients, 14 outils,
profil default et session partagée validés. Log :
`/private/tmp/webkitui-10342528-two-client-fresh.log`.
Le contrôle indépendant du verrou après ce second passage a réussi dans la limite
de 40 secondes, rc=0 : `Independent host lease check: released`.
L'écart de manifeste reste ouvert ; aucun paquet n'a été réinstallé pour le masquer.

## Suite fonctionnelle

Le rapport Volvo est consigné avec distinction entre observations utilisateur et
lecture du code. Le prédicat textuel n'impose pas la visibilité ; le clipping des
ancêtres n'est pas pris en compte par `isRendered`. Cela donne des fixtures à
écrire, pas une attribution certaine du défaut de layout au MCP.
Ni le rendu Volvo ni les incidents Apple Contact Us ne sont déclarés corrigés.
Ne pas utiliser une postcondition textuelle pour affirmer que les paramètres OAuth
ont été lus. Aucune opération dans le dépôt Éclair ou le compte Volvo autorisée
par cette reprise de maintenance.

## Suivi SiliconPass autorisé ensuite

Après un inventaire séparé, Kevin a autorisé l'installation/activation du service
SiliconPass et un remplissage synthétique. Le service est maintenant installé,
activé et testé avec succès ; le coffre personnel et l'app SiliconPass installée
n'ont pas été modifiés. Voir les preuves, limites et commande de désactivation
dans [le rapport SiliconPass du 21 septembre](../diagnostics/2026-09-21-siliconpass-service-and-fill.md).
