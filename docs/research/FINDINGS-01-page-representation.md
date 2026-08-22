> ⚠️ **PÉRIMÉ — voir `SYNTHESE-plan.md`.** Cette note disait « l'arbre
> d'accessibilité a gagné ». La mesure contrôlée (WorkArena, avril 2026) dit
> l'inverse pour les modèles forts : HTML détaillé 73,3 % contre 55,8 % pour
> l'AXTree avec GPT-5.1-high. Conservée pour trace, ne pas s'y fier.

# Findings — page representation (première passe, 2026-08-21)

Recherche web menée par Claude, pas encore recoupée par un deep research complet.
Les chiffres viennent des sources listées en bas ; ceux marqués ⚠️ sont des
affirmations d'éditeur non reproduites indépendamment.

## 1. L'arbre d'accessibilité a gagné

C'est déjà le défaut des outils sérieux : **Playwright MCP et Chrome DevTools MCP
travaillent sur des snapshots d'arbre d'accessibilité**, pas sur des captures
d'écran.

Ordres de grandeur cités :

| représentation | tokens par page |
| --- | --- |
| arbre d'accessibilité | ~200–400 |
| ce qui intéresse vraiment le modèle | ~2 000–3 000 |
| HTML brut | 15 000–30 000 |
| capture d'écran | coûteuse, et le modèle doit encore l'interpréter |

Conséquence directe pour `webkitui-mcp` : la capture d'écran doit devenir
l'exception documentée (canvas, graphiques, glisser-déposer), jamais le mode par
défaut.

## 2. WebMCP — le vrai bleeding edge

Un site peut **déclarer ses actions** au lieu de laisser l'agent deviner :
`navigator.modelContext`.

- 10 février 2026 : W3C publie le Draft Community Group Report
- Chrome 146 Canary derrière un flag, puis **origin trial public en Chrome 149**
  (annoncé à Google I/O, mai 2026)
- ⚠️ Démo de réservation de vol annoncée à **500 000 → 1 000 tokens**, 30–60 s →
  1–2 s. Chiffre éditeur, à traiter comme une borne, pas comme une mesure.

**L'opportunité** : WebMCP est spécifié côté page, pas côté Chrome. Un navigateur
WebKit qui sait lire `navigator.modelContext` quand le site l'expose, et retomber
sur l'arbre d'accessibilité sinon, serait au niveau du standard émergent — et
Safari/WebKit n'a rien annoncé.

## 3. Le piège que nous venons de mesurer nous-mêmes

Une source note que les MCP navigateurs actuels « enveloppent l'arbre
d'accessibilité dans des serveurs MCP avec des dizaines de définitions d'outils,
et chaque schéma mange du contexte ».

C'est exactement ce que j'ai mesuré aujourd'hui sur ta machine : **18 027 octets
de noms d'outils** pour 419 outils, avant même qu'une page soit ouverte.
`webkitui-mcp` a 19 outils. La surface d'outils est un coût, au même titre que la
page.

## 4. Une méthode d'évaluation utilisable tout de suite

**Minimal Failure Set** (arXiv 2605.29397) : le plus petit ensemble d'éléments
HTML dont la suppression fait échouer la tâche. La « couverture » — la fraction
des cas où une réduction préserve intégralement ce MFS — **corrèle fortement avec
le taux de succès end-to-end**, sans accès web ni inférence LLM.

Les auteurs mesurent **plus de 100× d'accélération** du temps d'évaluation : leur
évaluation end-to-end de 11 méthodes sur 32 configurations et 33 tâches de
WorkArena L1 coûtait 232,4 heures cumulées.

C'est la brique qui manque à notre banc : une métrique de réduction vérifiable
sans juge LLM, dans la même logique que le banc de délégation locale.

## Ce qu'il reste à vérifier

- Les chiffres 200–400 tokens viennent de billets techniques, pas d'un papier.
- Aucune reproduction indépendante de la démo WebMCP.
- Rien trouvé encore sur la **stabilité des identifiants d'éléments** entre deux
  rendus — c'est la question 3 du prompt de deep research, elle reste ouverte.

## Sources

- https://arxiv.org/abs/2605.29397
- https://arxiv.org/pdf/2506.16042
- https://arxiv.org/pdf/2512.13438
- https://arxiv.org/pdf/2604.17817
- https://zylos.ai/research/2026-02-22-webmcp-browser-native-ai-agent-integration/
- https://developer.chrome.com/blog/chrome-at-io26
- https://dev.to/thousand_miles_ai/webmcp-in-chrome-149-web-pages-get-a-tool-api-for-ai-agents-bfi
- https://www.buildmvpfast.com/blog/webmcp-browser-standard-ai-agents-2026
- https://agentmarketcap.ai/blog/2026/04/07/chrome-firefox-native-agent-apis-2026-browser-agentic-primitives
- https://www.searchenginejournal.com/the-accessibility-tree-is-how-ai-agents-read-your-site-its-breaking/578171/
- https://www.scrapeless.com/en/blog/accessibility-tree-web-scraping
- https://sderosiaux.medium.com/chrome-agent-a-new-llm-native-browser-automation-tool-written-in-rust-854a16e9ed38
