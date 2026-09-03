# SiliconPass physical synthetic credential gate

Date: 2026-08-29
Repository HEAD: `72ad3504cba0e849c4da9bb88c281ba7ddb2f7c2`
Status: `PASS — physical fill and rotation against an ephemeral synthetic vault`

## Scope and authority

The user authorized the local physical SiliconPass fill and rotation gates.
Both runs used fresh synthetic canaries in an ephemeral qualification vault,
the installed native WebKitUI MCP authority and system-owned user
authentication. No real website, account or credential was used; neither flow
submitted a form. No notarization, upload, publication, portal mutation, commit
or push occurred.

## Fresh signed artifacts

- Provider:
  `/private/tmp/webkitui-siliconpass-physical-20260829/provider/siliconpass-credential-broker-synthetic-provider`
- Provider identifier / Team: `com.lorislab.siliconpass` / `TDV6D5L785`
- Provider SHA-256:
  `f18316a1887b11bdc14028dc7058c93808bdb2f1540168e3b2a8125e228879e9`
- Validator:
  `/private/tmp/webkitui-siliconpass-physical-20260829/validator/credential-broker-physical-validation`
- Validator identifier / Team: `com.lorislab.webkitui-mcp` / `TDV6D5L785`
- Validator SHA-256:
  `25f5b6da2338cee425aecc0faf7f0ca7518684ae005788352f2324cf3ec9a8a2`
- Both executables passed strict signature verification with Developer ID,
  hardened runtime and secure timestamp.

## Results

### Fill

- Run ID: `A27B9463-37ED-4B17-9917-77160C5CD67E`
- MCP tool: `browser_fill_siliconpass`
- Native receipt: `filled`
- Username and password canaries matched: yes
- Submission count: `0`
- Provider exit / validator exit: `0` / `0`
- Synthetic vault wiped and qualification root absent after completion: yes

### Rotation

- Run ID: `6EF7220C-2B58-415F-A6D6-D1C0351DAC03`
- MCP tool: `browser_rotate_siliconpass_password`
- Native receipt: `changed`
- New password generated: yes
- Secret released to MCP: `false`
- Submission count: `0`
- Provider exit / validator exit: `0` / `0`
- Synthetic vault wiped and qualification root absent after completion: yes

## Interpretation

This closes the local physical synthetic path for one qualified SiliconPass
provider: signed same-Team provenance, visible authorization, system-owned user
authentication, secretless MCP rotation and deterministic cleanup all passed.
It does not prove compatibility with real provider accounts or websites, other
authentication configurations, clean-Mac installation, accessibility, or
public distribution.

## Product asset observation

At the time of this credential gate, the source and installed app did not have a
configured icon. This was subsequently resolved for source and unsigned preview
packaging; see `docs/diagnostics/2026-08-29-app-icon-integration.md`. The
currently installed signed app still predates that asset change.
