# Multi-session et multi-fenêtre — plan

Date : 2026-09-23. Cartographie en lecture seule, puis étape 0 implémentée.

## Constat

- Production : `maximumSessions: 1`, bail exclusif sur l'hôte
  (`AquaBroker/main.swift`, `CLI/main.swift`). Le registre crée un bail `flock` par
  session : une deuxième session dans le même processus lève `hostControllerBusy`.
- Toutes les sessions partagent le magasin `.default()`, et chaque runtime y pose son
  proxy SOCKS épinglé : une deuxième session écrase celui de la première.
- Cookies partagés par profil : deux agents sur `default` partagent leurs connexions.
- État global à indexer par session : `GoalDelegationMonitor`, fenêtre compagnon
  (`existingHandle`), présentation des confirmations (sans identité client).
- Déjà prêt : `session_id` sur tous les outils, observations/approbations/limites par
  session, contrôle de propriété à chaque appel.
- Popups : `createWebViewWith` renvoie nil ; sous verrou d'origine la demande était
  annulée en silence avant même `createWebViewWith`.

## Étapes

0. **Fait** : lien `target=_blank` activé depuis le cadre principal suivi dans la même
   vue, sous la même politique qu'un lien sans cible (verrou d'origine, refus
   cross-origin). Sous verrou, un `_blank` étranger est refusé et signalé
   (`followedInSameView=false`, destination) au lieu d'être annulé en silence.
   `window.open()` par script reste refusé et signalé.
1. **Fait** : bail d'hôte au niveau du processus (une 2e session le réutilise, un
   autre processus reste refusé, le bail part avec la dernière session) ; proxy
   partagé par magasin (cache faible, chaque runtime le tient) ; `openOrReuse` rend
   d'abord une session libre du même profil, puis en ouvre une nouvelle s'il reste de
   la place, sinon une session possédée ailleurs ; `GoalDelegationMonitor` indexé par
   délégation, le bouton stop les révoque toutes, une reconnexion n'efface que les
   siennes.
2. **Fait (broker)** : `maximumSessions: 3` ; CLI à 1. Décision : profil `default`
   partagé (toutes les connexions de l'utilisateur y sont et tous les agents agissent
   pour lui) ; profils isolés possibles plus tard, en option. Chaque confirmation
   native commence par « Requested by agent (self-reported name) », nom nettoyé et
   borné ; la fenêtre de contrôle humain porte le nom de l'agent ; « Forcer le
   rendu » agit sur toutes les sessions. Restent : file globale des confirmations,
   liste des sessions dans la fenêtre compagnon.
3. **Fait pour l'humain (3a)** : sous contrôle humain, un popup devient une vraie
   fenêtre construite depuis la configuration de WebKit (même profil, même proxy,
   `window.opener` et `postMessage` fonctionnels) ; au plus 4 ; alertes et
   confirmations JavaScript répondues par la personne ; toutes fermées quand l'agent
   reprend et à la destruction du runtime. Sous contrôle agent, rien ne change.
   **Reste (3b)** : popups pilotables par l'agent — chaque approbation nomme
   (session, window_id, origine), `switch_window` invalide les observations.

## Spike magasins nommés (2026-09-23, macOS 27)

Script autonome, deux profils `WKWebsiteDataStore(forIdentifier:)` :

- cookie + `localStorage` écrits dans A relus par un autre processus : OK ;
- B ne voit rien de A : OK ;
- `remove(forIdentifier:)` efface, mais **plante (SIGSEGV dans
  `RunLoop::dispatch`)** si aucun WKWebView n'a encore été créé dans le processus.
  Après initialisation de WebKit : OK. Toujours supprimer depuis un processus où
  WebKit tourne déjà (le broker), jamais depuis un outil en ligne de commande nu.
- L'énumération `fetchAllDataStoreIdentifiers` reste à éviter : l'app tient sa propre
  liste d'identifiants.

## Décisions par défaut

- Profil isolé par client ; partage explicite seulement.
- 3 sessions × 4 fenêtres ; au-delà `capacity_reached`.
- Magasins nommés à valider sur macOS 27 (seule l'énumération plante) : spike d'abord,
  repli « default seul, 1 session » en cas d'échec.
- Une popup ne devient jamais active toute seule.

## File unique des confirmations (fait)

`ConfirmationTurnstile` : un seul panneau natif à la fois pour toute l'app, premier
arrivé premier servi. L'attente ne compte pas dans le délai du panneau ; une
annulation pendant l'attente rend `cancelled` sans rien afficher ; `state` vaut
`pending_native_confirmation` pendant l'attente. Test : deux présentateurs, journal
`start,end,start,end` (sans le tourniquet : `start,start,end,end`).

## Bug système observé : Screen Time à la destruction d'un WKWebView

Un passage debug en parallèle a planté (SIGABRT) :
`-[WKWebView dealloc]` → `_uninstallScreenTimeWebpageController` →
`-[STScreenTimeConfigurationObserver dealloc]` → `removeObserver:forKeyPath:` lève
`NSInternalInconsistencyException` (observateur déjà retiré). Bug macOS 27
(ScreenTime/WebKit), intermittent sous charge. Le broker détruit un WKWebView à chaque
fermeture de session : risque réel mais rare. `showsSystemScreenTimeBlockingView=false`
n'a pas pu être relié au contrôleur (sonde KVC nulle dans les deux cas) : non appliqué
faute de preuve. À surveiller ; à signaler à Apple (Feedback) avec cette pile.
