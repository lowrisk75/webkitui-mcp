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
1. Registre : bail au niveau processus + N sessions (N=1 en production). Proxy par
   magasin (magasin nommé par session ou proxy partagé à compteur de références).
   `GoalDelegationMonitor` par session.
2. Broker seulement : `maximumSessions: 3`, profil nommé isolé par client par défaut
   (opt-in `shared_profile` avec confirmation native), en-tête client/session dans
   chaque confirmation, file globale des confirmations, un seul handoff visible
   (`handoff_busy`), fenêtre compagnon par session. La CLI reste à 1.
3. Vraies fenêtres popup dans une session (OAuth, `window.opener`) : max 4, liées à un
   geste ou une approbation, chaque approbation nomme (session, window_id, origine),
   `switch_window` invalide les observations.

## Décisions par défaut

- Profil isolé par client ; partage explicite seulement.
- 3 sessions × 4 fenêtres ; au-delà `capacity_reached`.
- Magasins nommés à valider sur macOS 27 (seule l'énumération plante) : spike d'abord,
  repli « default seul, 1 session » en cas d'échec.
- Une popup ne devient jamais active toute seule.
