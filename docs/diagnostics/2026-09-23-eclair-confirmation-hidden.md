# Éclair — confirmations « indisponibles » après un handoff_resume

Date : 2026-09-23. Source : `audit-output/feedback-eclair-2026-09-23-confirmation-unavailable.md`.

## Constat

Après `handoff_resume`, trois confirmations (navigate, deux clics) ont expiré en 60 s,
« The confirmation helper did not present a prompt », et Kevin n'a rien vu.

## Preuves

- `log show` : l'assistant `webkitui-mcp-confirm` (pid 66997) a démarré à 17:41:37.
- WindowServer, même seconde : `keyboardFocus <keythief> -> pid 66997` — le panneau a
  été présenté et a pris le focus clavier, sur l'unique écran.
- Il a donc été affiché puis est resté invisible (recouvert, ou sur un autre Space),
  jusqu'au délai de 60 s. La signature de l'assistant, que la remédiation désignait, était
  correcte.
- `approval_mode: mcp` passe par l'assistant natif : voulu pour un client en protocole
  antérieur à 2026-07-28 (Claude Code), mais nulle part dit.
- Titre « agent “unknown-client” » : les relais de ces sessions ont été lancés avant le
  rejeu d'`initialize` (0.6.12) ; un processus déjà lancé garde l'ancien code.

## Corrections

- Panneau au niveau `popUpMenu`, au-dessus du Dock, de la barre de menus et des panneaux
  flottants des autres apps.
- L'assistant vérifie `occlusionState` 2 s après la présentation ; un panneau jamais visible
  sort avec le code 4 → issue `hidden`, rapportée en ~2 s au lieu de 60.
- Trois messages distincts : `hidden` (caché : fermer les surcouches ou changer de Space),
  `timed_out` (présenté, sans réponse), échec de l'assistant (seul cas qui renvoie vers la
  signature). `confirmation_presented` vrai pour les deux premiers.
- Descriptions de `approval_mode` : le repli natif pour les clients antérieurs est dit.

## Vérifié

- Assistant recompilé, affiché 4 s sans intervention : reste ouvert (pas de faux « caché »).
- Test : un assistant qui sort en 4 donne `hidden`.

## Reste

- Reproduire en vrai : handoff → « Terminé » → handoff_resume → navigate.
- Relancer les sessions Claude/Codex dont le relais date d'avant 0.6.12.

## Repro réelle (2026-09-23, 0.6.21 installée)

Session Home Assistant en `human_step_completed` → `handoff` (reprise) → panneau
présenté et accepté, observation fraîche → `browser_navigate` → panneau présenté et
accepté, document prêt en ~2 s. Aucun `hidden` ni `timed_out`. Reste : relancer les
sessions Claude/Codex antérieures à 0.6.12.
