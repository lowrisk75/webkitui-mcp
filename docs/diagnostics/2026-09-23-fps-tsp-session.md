# Session FPS/TSP et ANTAI — corrections

Date : 2026-09-23. Source : `Documents/Emilie/FPS-TSP/WebKitUI-feedback-2026-09-23.txt`.

| Constat | Cause | Correction | Preuve |
| --- | --- | --- | --- |
| Fenêtre « Contrôle humain » restée derrière le terminal | Depuis macOS 14, une app ne prend plus le premier plan à une autre ; l'activation seule ne suffit pas | Fenêtre au niveau flottant à la présentation, rebond du Dock ; retour au niveau normal dès que l'app devient active | Revue de code ; validation physique à faire |
| `handoff_resume` : 57 477 caractères malgré le compact | Compact par défaut = 150 lignes avec boîtes et qualité de localisateur | En compact : 40 lignes par défaut, champs rôle/nom/href/état ; `maximum_elements` et `compact: false` inchangés | Schéma mis à jour |
| Champs désactivés sans valeur (adresse postale) | La valeur n'était exportée que pour un champ modifiable | Valeur exportée pour tout champ visible et non sensible, désactivé ou en lecture seule compris | Test : adresse et ville lues, mot de passe désactivé et champ caché non |
| Session disparue → « Internal error », puis `unknownSession` | `unknownSession` remontait comme erreur JSON-RPC interne | Résultat d'outil `session_expired` avec l'étape suivante | Test sur `browser_observe` et `browser_read_text` |
| `status` contradictoire, `unknown-client` | Corrigé en 0.6.12 (propriété par client, rejeu d'`initialize` par le relais) | — | Voir `2026-09-23-velya-tailscale-and-ownership.md` |

Hors WebKitUI : les refus « auto mode classifier » viennent de Claude Code avant tout
appel au serveur ; aucune confirmation native n'a été montrée.

Non traité : téléchargement `blob:` même origine (1.5), contenu chargé après
`ready` (1.6).
