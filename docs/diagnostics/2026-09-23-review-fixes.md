# Revue du code du 2026-09-23 (0.6.10 → 0.6.17) — corrections

Revue en lecture seule de `f7036db..HEAD`. Chaque défaut ci-dessous est corrigé ; les
tests marqués « prouvé » échouent sans la correction.

| # | Défaut | Correction | Test |
| --- | --- | --- | --- |
| 1 | Remplissage agent : `selectAll` natif pouvait remplacer tout un éditeur, ou un autre champ si la page déplaçait le focus | Resélection JS juste avant la saisie, seulement si le focus est encore dans l'élément armé (ou son hôte d'édition), et seulement de son contenu ; reçu `input` écouté sur l'hôte d'édition | Bloc d'éditeur remplacé seul ; vol de focus → `targetNotActionable`, autre champ intact |
| 2 | Remplissage SiliconPass humain : le mot de passe pouvait atterrir là où la page déplaçait le focus | Barrière `beforeinput` dans tous les cadres du document pendant le remplissage ; contrôle humain, document et type `password` revérifiés avant chaque champ ; arrivée vérifiée par longueur ; `select()` du champ au lieu de `selectAll` | Prouvé : sans barrière, le mot de passe tombe dans le champ piégé 3 fois sur 3 |
| 3 | Champ identifiant choisi par simple position (recherche du site possible) | Signal requis (autocomplete username/email, type email, nom ou id user/email/login/account/identifier) dans le formulaire ou le conteneur proche ; sinon mot de passe seul | Boîte de recherche intacte, mot de passe rempli |
| 4 | Les cadres des popups entraient dans le registre de la page principale | Messages de script ignorés s'ils ne viennent pas de la vue principale | Prouvé : 4 cadres au lieu de 1 sans filtre |
| 5 | Un accès Tailscale valait pour toute page de toute session (CSRF possible vers le service) | Règle de contenu WebKit par origine accordée : bloquée sauf si la page principale est cette origine ; installée dans toutes les sessions avant la navigation ; texte de confirmation précisé | Prouvé : sans règle, une page étrangère atteint le service |
| 6 | Port > 65535 : conversion `UInt16` pouvait faire planter le broker | Port validé à l'entrée (1…65535) et `UInt16(exactly:)` | Port 70000 → `-32602` |
| 7 | File des confirmations sans limite de temps | Attente plafonnée (90 s) → `timed_out`, fenêtre jamais affichée | Test dédié |
| 8 | Attente de chargement déclenchée par des jauges permanentes | Seules les barres de progression indéterminées et les petits éléments `aria-busy` comptent | Tests existants |
| 9 | Titre de la fenêtre humaine : mauvais agent après un transfert, nom non étiqueté | Nom fixé par le client qui demande le handoff ; affiché entre guillemets, « self-reported » | — |
| 10 | `same_row_label` : l'action ne sautait pas un libellé sensible comme l'observation | Même filtre (sensible, opaque) des deux côtés | Prouvé : `targetNotFound` sans la correction |
| 11 | Proxy partagé : une 2e instance du même magasin nommé n'était pas configurée | `proxyConfigurations` toujours posé | — |
| — | Relais : un rejeu raté abandonnait la 2e tentative | La 2e tentative se reconnecte | — |
| — | Vérification DNS bloquante sur le pool coopératif, sans délai | File dispatch dédiée, abandon après 3 s (le proxy décide toujours) | — |
| — | Observateur d'activation jamais retiré | Retiré à la reprise et dans `deinit` | — |
| — | Valeurs lisibles des champs désactivés : secrets courts | Termes sensibles élargis (clé d'API, codes de récupération/secours, clé privée, phrase de récupération) | — |
| — | « SiliconPass indisponible » pour un formulaire qui a changé | Message propre à `stale` (EN/FR) | — |
