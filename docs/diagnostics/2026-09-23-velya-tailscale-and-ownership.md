# Velya / Home Assistant via Tailscale — corrections

Date : 2026-09-23. Source : `Velya/audit-output/WEBKITUI_NATIVE_FEEDBACK_2026-09-23.md`.

| Constat | Cause | Correction | Preuve |
| --- | --- | --- | --- |
| `navigationFailed("NSURLErrorDomain code=-1000")` vers `homeassistant.fox-inconnu.ts.net` | Le nom résout dans `100.64.0.0/10` ; le proxy épinglé refuse (`noPublicAddress`) et WebKit rapporte -1000 | `navigate` résout d'abord avec la même politique et lève `privateNetworkDestination(origin:)`, avec une remédiation qui dit que réessayer ne changera rien. Le proxy reste seul juge de chaque connexion | Essai réel sur le nom Tailscale (test temporaire, retiré) : erreur typée avec l'origine exacte ; test de remédiation permanent |
| `open(wait_timeout_ms)` rend tout de suite une session d'un autre client | L'attente ne couvrait que le bail d'hôte, pas la propriété d'une session réutilisée | La revendication de propriété est retentée jusqu'à l'échéance demandée | Revue de code ; tests serveur existants |
| `status` : `control_available: true` / « The agent holds this session » avec `owned_elsewhere` | Ces champs décrivent agent contre humain, pas quel client | Pour `owned_elsewhere` : `control_available=false`, `wait_only=true`, message et remédiation propres, `caller_action=wait_or_client_handoff` | Tests serveur existants |
| Holder `unknown-client`, version nulle | Le broker a redémarré (réinstallations du matin) ; le relais se reconnecte sans renvoyer `initialize`, donc le nouveau serveur ignore le client | Le relais garde le `initialize` du client et le rejoue en silence à chaque reconnexion | Test bout en bout avec faux serveur : B reçoit `initialize` puis `tools/list`, le client ne voit que sa réponse |

## Accès Tailscale confirmé

Demande de Kevin : régler l'accès. Une navigation vers un nom qui ne résout que dans
`100.64.0.0/10` lève `tailnetDestinationRequiresApproval` ; le serveur présente une
confirmation native « Allow Tailscale Access » pour l'origine exacte, accorde
(hôte, port) dans `TailnetOriginGrants` puis relance la navigation une fois.

- Le proxy n'utilise la résolution Tailscale que pour un (hôte, port) accordé, épinglée
  sous sa propre clé ; seules les adresses 100.64.0.0/10 sont acceptées.
- Autres plages privées, autre port, autre nom : toujours refusés.
- Accès oublié à la fermeture de l'app. Refus : `tailnet_access_declined`.
- Tests : proxy (refus avant, accès après, autre port et autre nom refusés), plage.
- Essai réel (test temporaire retiré) : sans accès → demande d'approbation ; avec →
  `https://homeassistant.fox-inconnu.ts.net/` chargé via le proxy, `ready`, titre
  « Home Assistant ».

Non reproduit : `fromOrigin` Home Assistant dans `latest_navigation` alors que la page
affichée restait Cloudflare.

## Validation

- Lint strict et `git diff --check` : rc=0.
- Debug (bundles en parallèle) : 135 + 196 + 18 + 90 + 56 = 495, plus 13 XCTest, 0 échec.
- Release, sérialisé comme la gate du projet (`-j 1 --no-parallel`) : deux passages
  complets, 495 + 13 chacun, 0 échec.
- Release en parallèle : sur 7 passages complets aujourd'hui, 2 ont perdu le résumé du
  bundle serveur en plein test (tests différents, rc=0, aucun rapport de crash). Le
  bundle serveur seul passe 4 fois sur 4. Cohérent avec la fragilité WKWebView sous
  bundles concurrents que la gate documente ; la fermeture de fenêtre ajoutée dans
  `isolated deinit` n'est pas exclue formellement.
