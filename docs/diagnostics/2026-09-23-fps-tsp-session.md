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

## Suite

| Constat | Cause | Correction | Preuve |
| --- | --- | --- | --- |
| `browser_download` → `networkBoundaryDenied` sur un document `blob:` du portail | `navigationOrigin(for:)` ne connaissait que http(s) : un `blob:` était sans origine, donc « autre origine » | Un `blob:` prend l'origine de son créateur (règle HTML) ; un `blob:` imbriqué reste sans origine | Test : PDF généré par la page en `blob:` téléchargé, octets et empreinte vérifiés ; sans la correction, exactement `networkBoundaryDenied` |
| Premier `read_text` : « Chargement en cours », 0 ligne, `usable`/`ready` | Le signal de chargement ne regardait que la page entière, pas une zone | `read_text` attend jusqu'à 3 s qu'aucun élément visible ne soit un simple indicateur de chargement (`aria-busy`, `progressbar`, texte « Chargement en cours »/« Loading… ») ; sinon `loadingIndicatorVisible=true` et une consigne de relecture | Test : lignes du tableau lues au premier appel ; indicateur permanent signalé |

Non traité : les fichiers de l'historique affichés comme simple texte de cellule, sans
lien, restent inaccessibles tant que le site ne les expose pas.
