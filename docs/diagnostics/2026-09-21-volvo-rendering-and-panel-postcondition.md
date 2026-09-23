# Volvo: rendu initial vide et panneau non visible

Date : 2026-09-21. Mission : `10342528-D73D-44AC-9868-B8C6AF5A7E92`.
Source des observations portail : rapport utilisateur de la session Volvo,
pas une reproduction indépendante par la présente session de maintenance.
Aucun cookie, jeton, secret, contenu OAuth ou capture de compte conservé ici.

## Constats rapportés

- Backend `native_webkit`, politique `trusted_local`, profil `default`.
- Première navigation vers `https://developer.volvocars.com/` : `ready`, mais
  `empty_or_unusable`. Après attente : titre correct, `readyState=complete`,
  162 mutations, aucun contenu ni contrôle rendu ; capture entièrement blanche.
  Un alert anonyme de rectangle `[-1,-1,1,1]` était le seul élément exposé.
- Handoff/reprise : même document, toujours vide. Un reload explicitement demandé
  a créé un nouveau document, `usable`, sans redirection. Observation suivante :
  215 mutations, 66 éléments, 64 contenus rendus, 40 contrôles ; « Log in » visible.
- La reprise humaine suivante a confirmé la connexion (account, Log out, page
  `/account/` et application Eclair). Ce constat remplace seulement l'état
  initial non connecté ; il ne prouve aucune lecture des paramètres OAuth.
- Premier clic sur le summary Eclair : `targetGeometryChanged`. Après une nouvelle
  observation, clic natif sur le parent summary : geste trusted et reçu `verified`
  pour `semantic_text_appears = Eclair Application Client Details`.
- Le bouton Details était d'abord hors viewport, puis `covered` après scroll.
  Aucun clic n'a été exécuté sur cette cible couverte. Les captures ne montraient
  aucun détail entre le summary avec chevron ouvert et Create new application.
- Session rendue à l'humain. Statut de publication, type du client OAuth, méthode
  d'authentification et URI de retour non lus. Aucune mutation du portail.

Le HTTP 401 OAuth d'Éclair reste un problème distinct. Aucun lien causal n'est
établi avec le rendu blanc ou le panneau. Le mainteneur WebKitUI n'a pas inspecté
le code Éclair ni son enregistrement OAuth dans cette reprise.

## Vérification du code à f7036db

1. `MCPServer.swift`, `ActPostcondition.semanticTextAppears` : comparaison exacte
   des entrées accessibleName/label/text/value de l'état canonique. Aucun prédicat
   de visibilité ni hit testing n'est associé à cette comparaison.
2. `CanonicalPageState.swift` : noms, labels et textes des éléments observés sont
   ajoutés sans condition de visibilité. La valeur possède un filtre distinct.
   Le champ `@visible` est séparé ; sa présence ne contraint pas la comparaison.
3. `WebKitRuntime.swift`, `isRendered` : taille, client rects et ancêtres
   hidden/inert/aria-hidden/display/visibility sont examinés. Le clipping par
   overflow des ancêtres n'est pas intersecté avec le rectangle du descendant.
   Une opacité nulle d'ancêtre est intentionnellement signalée sans élimination.
4. `actionabilityOf` vérifie le viewport et le hit testing au centre : conserver
   le refus `covered`. Le retirer ne réparerait pas une preuve de visibilité.

Cela explique pourquoi le contrat textuel ne prouve pas une ouverture visuelle.
Cela ne prouve pas la cause du défaut de layout observé chez Volvo. Une réussite
du clic et de sa postcondition textuelle n'est pas une lecture des paramètres.

## Régressions à traiter, par priorité

1. **Preuve de panneau exploitable** : fixture locale où un descendant garde un
   rectangle sous un ancêtre `height:0; overflow:hidden`, puis panneau partiellement
   clippé, animation d'ouverture, opacity d'ancêtre et overlay. Mesurer séparément
   présence sémantique, rendu, intersection visible, réception des événements et
   état expanded/open. Une preuve visuelle doit rester insatisfaite tant que le
   texte n'est pas visible ; ne pas assimiler toute présence textuelle à cela.
   Inclure des témoins positifs (texte non interactif, panneau ouvert, élément
   hors écran devenant visible après scroll) avant de changer le contrat existant.
2. **Première navigation puis reload** : fixture déterministe d'hydration différée
   et comparaison publique bornée sur l'URL Volvo, dans une session disponible.
   Conserver séparément navigation terminée, quiescence et utilisabilité ; le
   premier `empty_or_unusable` était approprié. Aucun reload automatique de
   formulaire ou boucle de récupération.
3. **Schéma client** : contrôler le schéma wire de `browser_act` et son exposition
   par l'adaptateur client. `unknown & unknown...` est un symptôme rapporté ; les
   erreurs operation/postcondition manquantes étaient des erreurs d'appel, pas
   des erreurs du portail. Le source contient déjà des branches de schéma typées.
4. **Instrumentation consentie et bornée** : erreurs de navigation, terminaison
   WebContent, ressources en échec et exceptions JS, avec exclusion des secrets,
   requêtes, headers et cookies avant export. Aucun collecteur ajouté ici.

Ni le site, ni WebKitUI, ni le réseau ne sont désignés comme cause du blanc faute
de reproduction et de traces discriminantes. Ne pas transférer l'authentification
à un autre navigateur pour réaliser un témoin.
