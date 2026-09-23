# SiliconPass — service installé et remplissage synthétique validé

Date : 2026-09-21. Mission : `10342528-D73D-44AC-9868-B8C6AF5A7E92`.

## Autorisation et périmètre

Kevin a donné « go for it » à la mise en place du service SiliconPass et à un
remplissage sur compte de test. Exécution limitée au service local et à une
fixture en mémoire ; aucun coffre personnel ouvert, aucun compte réel utilisé,
aucun formulaire soumis. `/Applications/SiliconPass.app` n'a pas été remplacé.
Le dépôt SiliconPass était déjà fortement modifié ; aucun fichier n'y a été édité.
Aucun commit, upload, notarisation ou publication.

## Installation

- Paquet : `~/Applications/SiliconPassCredentialBrokerManager.app`.
- Gestionnaire : `com.lorislab.siliconpass.credential-broker-manager`.
- Service : `com.lorislab.siliconpass.credential-broker`.
- Signature locale Developer ID, Team `TDV6D5L785`, hardened runtime,
  sans `get-task-allow`, sans horodatage ni notarisation. Vérification stricte
  du helper et du paquet réussie ; ce n'est pas une livraison publique.
- Gestionnaire compilé depuis `Tools/CredentialBrokerManager/main.swift`,
  arm64, cible macOS 14, optimisation Release. Paquet assemblé avec le script
  existant `scripts/package-credential-broker.sh` et le plist LaunchAgent source.
  Métadonnées du gestionnaire local : version 0.1.0, build 20260921.
- Service compilé depuis le checkout courant SiliconPass, produit SwiftPM
  `siliconpass-credential-broker-service`, Release arm64, `-j 1`.
- Source SiliconPass : HEAD `b4ea0fa34467fbc470d802c61339262d31effdcc`, arbre dirty.
  SHA256 du diff suivi contre HEAD au relevé final :
  `68950e8ed9be231dc4d1a84bf3d5d26476119c1738d6124330bb18296dd06367`.
- Scratch isolé sur disque externe :
  `/Volumes/DeveloperStorage/BuildScratch/Auto/SiliconPass-webkitui-20260921`.
- Enregistrement SMAppService : `enabled`, `succeeded=true`, rc=0.
  Contrôle final hors sandbox : `enabled`, job running, PID 94456, une exécution.
  Un `notFound` obtenu depuis le sandbox a été invalidé par ce contrôle direct ;
  ne pas le confondre avec une désinstallation effective.

## Preuve physique actuelle

Run : `CA07B8A3-171B-427A-9A21-E279ABDE0177`.

1. Provider de qualification reconstruit depuis SiliconPass, signé sous
   `com.lorislab.siliconpass`. Il crée son propre coffre éphémère et enregistre
   son endpoint auprès du **service installé**. `syntheticOnly=true`, ready.
2. Harness WebKitUI `credential-broker-physical-validation`, issu du build de
   production courant, signé sous `com.lorislab.webkitui-mcp`. Page chargée
   en mémoire avec l'origine de fixture `https://fixture.invalid/login` ; aucun
   site réel visité. Il exerce le vrai client XPC, le serveur MCP et le sink privé.
3. Confirmation native SiliconPass et authentification système conservées.
   Aucun remplacement de l'autoriseur par une approbation automatique.
4. Résultat terminal, harness **rc=0** :

```json
{"brokerReceipt":"filled","mcpTool":"browser_fill_siliconpass","passwordCanaryMatched":true,"submissionCount":0,"usernameCanaryMatched":true}
```

5. Provider **rc=0**, `brokerProvider=qualified`, `syntheticVaultWiped=true`.
   Absence du répertoire exact de qualification vérifiée indépendamment :
   `~/Library/Application Support/CredentialBrokerQualification/CA07B8A3-171B-427A-9A21-E279ABDE0177`.

Logs locaux :

- `/private/tmp/siliconpass-broker-service-build-20260921.log`
- `/private/tmp/siliconpass-broker-provider-build-20260921.log`
- `/private/tmp/siliconpass-broker-manager-build-20260921.log`
- `/private/tmp/siliconpass-broker-20260921/provider-fill.log`
- `/private/tmp/siliconpass-broker-20260921/validator-fill.log`

## Empreintes SHA256 des exécutables signés

| Artefact | SHA256 |
| --- | --- |
| Gestionnaire installé | `7adda2dc918285bcbb6c33252f0cb6c4eb4b6c038205f442f1bc36cfddfc2f70` |
| Service installé | `941753ddc42cdfdff002a991a5919bdf62fc479f86fb203a3983acc6d40c19f5` |
| Provider de qualification | `666b0f7ea0b1e7791ee927356a5dea6415313e0a23454346bda84cbc08987814` |
| Harness WebKitUI | `7a673497c8d1da603beb10d3d6abb0bf7e2af3987ac7fb55b79f45cba5e98bf4` |

## État laissé et limites

Le gestionnaire reste installé et le service activé, comme demandé. Le provider
temporaire et le harness ont terminé ; aucun coffre synthétique ne subsiste.
Le test valide le service installé avec un provider synthétique signé et le
harness WebKitUI, pas un remplissage depuis le coffre réel de l'app installée
dans une session Aqua existante. La rotation, testée historiquement, n'a pas été
rejouée ici. Aucun résultat sur un framework web réel, le redémarrage de macOS,
la notarisation ou la distribution ne découle de cette preuve.

Le code de production SiliconPass enregistre son provider uniquement quand le
coffre est déverrouillé et l'arrête au verrouillage. Une app déjà déverrouillée
ayant échoué avant l'installation du service peut nécessiter un nouveau cycle
verrouillage/déverrouillage ; cela n'a pas été imposé au coffre personnel.

Pour désactiver ultérieurement ce service, sans toucher aux coffres :

```sh
"$HOME/Applications/SiliconPassCredentialBrokerManager.app/Contents/MacOS/SiliconPassCredentialBrokerManager" --credential-broker-unregister
```

Cette désactivation n'a pas été exécutée. L'écart de manifeste de WebKitUI 0.6.9
décrit dans le handoff de reprise reste indépendant et ouvert.
