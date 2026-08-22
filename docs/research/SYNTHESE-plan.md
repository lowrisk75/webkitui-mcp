# Synthèse des 4 deep research → plan pour webkitui-mcp

Sources : les 4 rapports de `~/Downloads` (2026-08-21). Chiffres repris tels quels ;
ceux marqués ⚠️ sont des affirmations d'éditeur non reproduites.

---

## 0. Ce que je m'étais trompé hier

Ma note `FINDINGS-01` disait « l'arbre d'accessibilité a gagné ». **C'est faux.**

Étude WorkArena d'avril 2026, même modèle, seule la représentation change :

| modèle | HTML détaillé | arbre d'accessibilité |
|---|---|---|
| GPT-5.1 high | **73,3 %** | 55,8 % |
| Claude Sonnet 4.6 | **67,0 %** | 52,4 % |
| gpt-oss-20b high | 27,6 % | **46,4 %** |
| Llama-3.1-70B | 3,6 % | **18,2 %** |

Le HTML coûte **8,4× plus de tokens** (56 653 contre 6 720 par étape) et gagne
quand même — pour les modèles forts. Il perd lourdement pour les faibles.

**La compression n'est pas bonne en soi.** Elle est bonne quand la capacité
marginale du modèle à exploiter l'information est inférieure au coût de
distraction. C'est une propriété du **modèle**, pas seulement de la page.

Le « ~300 tokens » que j'avais cité vient de la doc Playwright MCP. Il est réel
pour leur snapshot, il ne dit rien du taux de succès.

---

## 1. Le créneau défendable

Le rapport concurrents est catégorique : **la navigation en lecture est
commoditisée, l'écriture authentifiée ne l'est pas.**

Web Bench (5 750 tâches, 452 sites), succès en écriture :

```
rtrvr.ai      65,6 %      Skyvern 2.0    46,6 %
Sonnet 3.7    39,4 %      Operator       32,3 %
Browser Use   11,4 %
```

Contre 63–88 % en lecture. Et les temps : 6 à 20 minutes par tâche.

**Ne pas attaquer** : entraînement de modèles visuels, flottes de proxys, fermes
de navigateurs, RL adversarial à grande échelle. Scale gagne.

**Terrain libre** : latence sous la couche modèle, fidélité de session
authentifiée, correction des écritures, garanties de confidentialité,
confinement des injections par provenance, récupération d'état périmé,
post-conditions vérifiables.

Ça tombe bien : c'est exactement ce qu'un moteur natif local peut faire.

---

## 2. Architecture d'observation

Pas une représentation. **Une couche adaptative.**

- État canonique côté navigateur : DOM + sémantique d'accessibilité + géométrie + pixels
- Projection par défaut vers le modèle : graphe sémantique compact
- **Promotion vers du HTML riche** quand le modèle est fort et la page structurée
- **Pixels seulement sur déclencheur** : canvas, graphique inaccessible, glisser-déposer, carte, curseur

Déclencheurs mesurés : VisualWebArena sous-ensemble « hard visual » → texte seul
4,8 %, GPT-4V+SoM 12,4 %. WebVoyager sur Booking.com → 2,3 % texte seul contre
43,2 % multimodal. Mais sur Allrecipes (texte), le texte seul gagne.

Et l'inverse est vrai : WebMall, capture d'écran seule → **0 %** en end-to-end.

### Historique : checkpoint + deltas

9 observations complètes = 39 011 tokens. 9 diffs = **13 670** (−65 %), succès
GPT-5.1-high **identique à 58,8 %**. Mais Gemini 2.5 Flash perd (50,0 → 48,2 %).

Donc : deltas + **snapshot canonique périodique**, jamais une chaîne de patchs sans fin.

### Le viewport n'est pas une frontière sémantique

AgentOccam : viewport 1 652 tokens → 25,9 %. Page entière 3 376 tokens → 31,7 %.
Page entière **simplifiée** 2 891 tokens → **37,1 %**.

Moins de tokens **et** plus de succès. Le viewport est une limite humaine, pas
une limite de tâche.

---

## 3. Adressage des éléments — le point que personne ne mesure

Le modèle veut un symbole court. Le navigateur veut un élément fraîchement résolu.
**Confondre les deux crée les échecs d'état périmé.**

Le bon modèle vient de Playwright : un `Locator` est une **règle de recherche**
re-résolue avant chaque action, pas un pointeur vers un nœud.

```
observation : e17  (identifiant court, éphémère)
interne     : recette de locator — rôle ARIA + nom accessible + data-testid
              + contexte DOM local + bbox comme corroboration
action      : re-résoudre, vérifier unicité + visibilité + stabilité + réception d'événements
échec       : invalider l'identifiant et ré-observer — jamais recliquer une coordonnée
```

⚠️ **Trou de mesure identifié par le rapport** : aucun benchmark ne publie de
taux d'échec par référence périmée. Les papiers agrègent tout en « échec de
grounding ». C'est instrumentable de notre côté :

`address_resolution_failed`, `address_now_ambiguous`, `logical_target_changed`,
`node_replaced_but_semantic_locator_recovered`, `coordinate_invalidated_by_layout_change`

Sans ces compteurs, un échec d'adressage passe pour un échec de raisonnement.

---

## 4. WebKit sur Apple Silicon

### À prototyper maintenant — tu es sur macOS 27 beta

`WKJSHandle` : références natives vers des objets JavaScript. C'est le gain
d'ergonomie que les protocoles type CDP avaient sur `evaluateJavaScript`.
Le rapport le désigne comme « la première API macOS 27 à prototyper ».

Aussi : `WKSerializedNode` (clonage de nœuds, shadow roots inclus),
`WKContentWorldConfiguration` (accès shadow root, inspectabilité),
`willSubmitForm`, lookup de cookies par URL.

### À supprimer

`WKProcessPool` est **déprécié** (Safari 26) et créer plusieurs instances
**n'a plus aucun effet**. Toute la folklore « un pool par isolation » est morte.

### Les limites réelles, à assumer

- **Hors écran ≠ headless.** WebKit arrête `requestAnimationFrame`, suspend les
  animations CSS/SVG, throttle les timers sur une page inactive. Ne jamais faire
  de « deux rAF » la primitive de stabilisation.
- **`takeSnapshot` ne capture pas tout** : effets 3D, filtres, reflets
  composités par le GPU manquent. Fallback = vraie fenêtre + capture de fenêtre.
- **Aucun quota mémoire par vue.** Pas de `maximumResidentMemory`. La seule
  frontière dure est un **processus helper externe** qu'on surveille et recycle.
- `webViewWebContentProcessDidTerminate` est un mode d'échec **normal**, à gérer
  avec un état checkpointable.

⚠️ Le rapport ne trouve **aucune mesure publique** WKWebView contre Playwright
Chromium sur la même page et la même machine Apple Silicon. Le « 45 Mo » de
ShotKit est un fork WebKit sans JavaScript, mesuré sous Windows. À benchmarker
nous-mêmes.

### « Chargé » n'est pas « prêt »

Prédicat **spécifique à la tâche** + quiescence sur les mutations *pertinentes*
+ deadline monotone native. Playwright déconseille explicitement `networkidle`.

---

## 5. Le modèle local sur Proxmox

**Verdict : oui, mais pas comme résumeur permanent.**

### L'ordre compte

```
rendu → nettoyage déterministe → classification page/tâche
      → extraction (lecteur OU DOM interactif)
      → élagage déterministe bon marché
      → SI NÉCESSAIRE : qwen3 4B Q4 comme trieur / extracteur de champs
      → paquet de preuves + spans exacts + provenance
      → modèle frontier
      → contrôle de capacités indépendant
      → exécution
```

L'extraction déterministe coûte **28–97 ms/page** et atteint déjà 0,80–0,86 de F1.
Les réducteurs LLM peuvent coûter **plus de latence qu'ils n'en économisent** —
FocusAgent dépassait 100 s par observation WorkArena.

### Le seuil de rentabilité

Pour que le préprocessing local fasse gagner du temps :

> le prefill local doit dépasser **1,25× le débit de prefill frontier**
> si l'on conserve 20 % de la page — avant même de payer la génération locale.

C'est exigeant. Un gain en **tokens** n'est pas un gain en **latence** : les deux
inégalités sont différentes.

### Ce qui valide notre correctif d'aujourd'hui

> « Ne pas activer le mode thinking par défaut. Routage, classification et
> extraction à haut rappel sont des tâches à sortie bornée ; sinon le travail
> autorégressif caché entre dans le chemin critique de chaque page. »

C'est exactement ce que j'ai mesuré : 896 tokens consommés en raisonnement,
**zéro caractère de réponse**, 86 s. Le rapport l'avait prédit.

### Quantisation

Qwen3-4B-Base : FP16 → MMLU 73,0 · GPTQ W4 → 70,9 · AWQ W4 → 66,7 · **AWQ W3 → 37,5**.
Perplexité 7,90 → 8,19 → 9,39 → **26,3**.

Q4 oui. **Q3 est une falaise**, pas un Q4 moins cher.

### Le résumé n'est pas un assainisseur

Étude 2026 sur 1,2 milliard d'URLs, 15,3 k injections validées, 5 200 essais :

- Texte plat aplati : **3,9 %** d'efficacité d'attaque (jusqu'à **8 %** sur petits modèles)
- HTML : **1,1 %** — la structure préserve des indices de provenance
- Petits modèles : détectent les injections **4,8 %** du temps
- Six cas où le modèle **a repéré** l'injection et a obéi quand même

Donc : aplatir une page en texte propre **augmente** l'exposition. Et un schéma
JSON contraint garantit la *forme*, pas la *valeur* — une injection peut remplir
`"trusted": true` dans un JSON parfaitement valide.

**La frontière de sécurité est le contrôle de capacités, pas un modèle qui juge
du texte.** CaMeL : 77 % des tâches AgentDojo avec garanties contre 84 % sans.

---

## 6. Provenance comme type de première classe

Chaque chaîne présentée au planificateur porte son origine :

```
USER_INTENT · USER_ENTERED_SITE_DATA · FIRST_PARTY_SITE_CONTENT
THIRD_PARTY_EMBED · EMAIL_FROM_EXTERNAL_SENDER · ADVERTISEMENT
TOOL_RESULT · PASSWORD_OR_SECRET · MODEL_GENERATED · LOCAL_TRUSTED_POLICY
```

Le runtime ne doit **jamais élever silencieusement** une classe vers une autre.
La faille omnibox d'Atlas est le cas d'école : une donnée d'attaquant ressemblant
à une URL a franchi une frontière de parseur et est devenue une instruction de
confiance.

Le rapport note que c'est « l'une des propriétés intellectuelles les plus
défendables pour une petite équipe » — parce que c'est de l'**architecture
runtime**, pas de l'entraînement de modèle.

---

## 7. Écritures transactionnelles

Web Bench identifie deux échecs récurrents :

1. L'agent **déclare la réussite avant de vérifier la post-condition** — une UI
   qui ressemble à un succès suffit.
2. L'identification d'élément échoue sur un contrôle trivial (bouton de
   fermeture de popup) et bloque tout ce qui suit.

Arithmétique : une primitive fiable à 98 %, répétée 50 fois → **36 %** de
trajectoires parfaites.

D'où : préconditions, post-conditions, idempotence, reçus. « Se désabonner de
ces cinq listes » compile en cinq transactions vérifiées indépendamment.

**Aucun navigateur grand public ne met ce modèle transactionnel au centre.**

---

## 8. Métrique d'évaluation

**Minimal Failure Set** : le plus petit ensemble d'éléments dont la suppression
fait échouer la tâche. La couverture corrèle avec le succès end-to-end —
0,82–0,88 sur WorkArena, 0,66–0,71 sur WebLinx — **sans accès web ni inférence**.

Gain : plus de **100×** sur le temps d'évaluation cumulé (232,4 h pour 11
méthodes × 32 configurations × 33 tâches en end-to-end).

C'est la brique qui manque à notre banc, dans la même logique que le banc de
délégation locale : une mesure vérifiable sans juge LLM.

Et il n'y a **pas de règle d'élagage universelle** : sur WebLinx retirer le texte
coûte 59,5 % de couverture ; sur WorkArena le texte coûte 30,5 % mais l'attribut
`value` seul en coûte 22,0 %.

---

## Ordre de travail proposé

1. **Instrumenter l'adressage** — les 5 compteurs. Personne ne les publie, on
   saura ce que les autres ignorent.
2. **Prototyper `WKJSHandle`** — tu es sur la beta, c'est le moment.
3. **Locator recipes** au lieu de pointeurs de nœuds.
4. **Provenance** sur chaque chaîne, dès la sérialisation.
5. **MFS coverage** comme métrique du banc.
6. **Checkpoint + deltas** pour l'historique.
7. Le modèle local en **trieur**, pas en résumeur — et sans thinking.
8. Post-conditions vérifiées pour toute écriture.

Ce qui reste ouvert et qu'aucun rapport ne tranche : la mesure mémoire réelle
WKWebView contre Chromium sur ta machine. À faire nous-mêmes avant de promettre
quoi que ce soit.

---

## 9. Ajout du NotebookLM « WebKITUI MPC » (interrogé 2026-08-21)

Le carnet confirme la synthèse ci-dessus et ajoute **un trou que les 4 rapports
ne nommaient pas** :

**Il n'existe aucun benchmark web vivant à l'épreuve de la contamination.**
Pas d'équivalent de SWE-bench-Live qui tirerait des tâches fraîches chaque mois.
Résultat : les classements saturent — WebVoyager culmine à **99,19 %**, WebArena
à **74,3 %** — pendant qu'Online-Mind2Web montre des chutes brutales sur le web
réel. Un score de leaderboard n'est plus une preuve de maturité.

Il reformule aussi les blocages comme **sept problèmes d'ingénierie, pas
d'échelle** : adressage périmé, vérification transactionnelle, latence sérielle
multimodale, authentification locale/SSO, anti-bot et proxys, effondrement de la
frontière de confiance, throttling hors écran.

Tous les sept sont hors de portée du scaling — et six sur sept sont dans notre
plan de travail. Le septième (anti-bot, proxys) est celui qu'il ne faut pas
attaquer : c'est un jeu d'échelle opérationnelle.
