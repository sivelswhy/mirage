# Mirage

Simulateur de localisation iOS pour macOS 26, interface Liquid Glass.

## Prérequis

- macOS 26 (Tahoe) et Xcode 26
- iPhone appairé, déverrouillé, **Mode développeur activé**
  (Réglages > Confidentialité et sécurité > Mode développeur, puis redémarrage)
- Homebrew

## Installation depuis une release

```bash
curl -fsSL https://raw.githubusercontent.com/sivelswhy/mirage/main/scripts/install.sh | bash
```

L'app vérifie ensuite les mises à jour à chaque lancement et propose un bandeau
non bloquant. Menu Mirage > Rechercher des mises à jour pour forcer le contrôle.

## Installation depuis les sources

```bash
./scripts/bootstrap.sh
open Mirage.xcodeproj
```

Le script génère le projet Xcode via XcodeGen et installe `pymobiledevice3`
dans `Resources/backend`, embarqué ensuite dans le bundle.

## Architecture

| Couche | Fichier | Rôle |
|---|---|---|
| Entrée | `App/MirageApp.swift` | Fenêtre sans barre de titre, raccourcis |
| Vue | `Views/ContentView.swift` | Carte plein cadre, pastille simulée |
| Vue | `Views/GlassControls.swift` | Panneaux flottants en Liquid Glass |
| État | `Core/SpoofSession.swift` | Appareils, tunnel, position, déplacement |
| Backend | `Core/PMD3.swift` | Exécution de pymobiledevice3 |
| Géo | `Geo/Geo.swift` | Cap, interpolation, import GPX |

## Le problème des privilèges

Sur iOS 17 et plus, `lockdown start-tunnel` exige root. La version actuelle
délègue à `sudo -n`, donc il faut une règle sudoers sans mot de passe :

```
echo "$USER ALL=(root) NOPASSWD: /chemin/vers/pymobiledevice3" | sudo tee /etc/sudoers.d/mirage
```

À remplacer par un démon `SMAppService` avant toute distribution.

## Limites connues

- La position réelle revient dès que le tunnel meurt
- Seul le GPS est simulé, pas le Wi-Fi scanning ni le baromètre
- Incompatible Mac App Store : sandbox et démon root inconciliables

## Intégration continue

Chaque commit sur `main` compile sur `macos-26` et publie un DMG en artefact,
conservé trente jours. Un tag `v*` déclenche en plus une release GitHub.

```bash
git tag v0.4.0 && git push origin v0.4.0
```

Les builds sont signés ad hoc, pas notarisés. Gatekeeper les bloque donc au
premier lancement, ce que `install.sh` contourne en retirant l'attribut de
quarantaine.
