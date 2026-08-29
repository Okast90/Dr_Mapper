# Mode Corridor Dédié (Linéaire) - Implementation Plan

Ajout d'un mode de cartographie linéaire ("Corridor Mapping") optimisé pour les infrastructures et structures longilignes (routes, clôtures, lignes électriques, cours d'eau, pipelines) sans modifier le fonctionnement existant de la cartographie surfacique (Grille).

## User Review Required

> [!IMPORTANT]
> - Le mode **Grille** (existant) reste le mode par défaut et conserve l'intégralité de son comportement.
> - Le mode **Corridor** sera sélectionnable via un sélecteur de mode dans l'onglet **Drone (Aircraft)** ainsi que sur la barre d'outils cartographique.
> - En mode Corridor, le tracé d'une polyligne GPS génère automatiquement une zone tampon paramétrable (ex: 20m, 50m, 100m) et les waypoints de vol optimisés (1 passage dans l'axe ou passages parallèles aller-retour avec recouvrement).

## Proposed Changes

---

### 1. Modèle de données & State Management

#### [MODIFY] [value_listeneables.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/shared/value_listeneables.dart)
- Ajouter l'enum `MappingMode { grid, corridor }`.
- Ajouter les propriétés observables :
  - `mappingMode` (défaut : `MappingMode.grid`)
  - `corridorWidth` (largeur de la bande tampon en mètres, défaut : 50m)
  - `corridorFlightLines` (nombre de passages : 1, 2 ou 3 lignes, défaut : 1)
  - `centerline` (liste des points GPS de la polyligne de référence)

---

### 2. Moteur de calcul géométrique & photogrammétrie

#### [MODIFY] [drone_mapping_engine.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/core/drone_mapping_engine.dart)
- **`generateCorridorBufferPolygon`** : Calcule le polygone fermé enveloppant la polyligne avec un décalage orthogonal de $\pm \frac{\text{width}}{2}$ pour l'affichage visuel et le calcul de surface.
- **`generateCorridorWaypoints`** :
  - **1 ligne (Axe central)** : Découpe chaque segment de la polyligne selon l'intervalle photo `pathSpacing = footprintHeight * (1 - forwardOverlap)` et place les waypoints de déclenchement caméra.
  - **2 ou 3 lignes (Multi-pass)** : Génère des passes parallèles décalées le long de la polyligne avec virages de transition optimisés et calcul de `sideOverlap`.
- **`calculateCorridorArea`** : Calcule la surface totale couverte en $m^2$.

---

### 3. Interface Utilisateur & Contrôles

#### [MODIFY] [aircraft.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/layouts/aircraft.dart)
- Ajouter une section **"Mode de Cartographie"** au sommet du menu Drone :
  - Sélecteur moderne : `[ ⊞ Grille Surfacique ]` | `[ ☱ Corridor Linéaire ]`.
- Lorsque le mode **Corridor** est actif :
  - Afficher les paramètres dédiés :
    - `Largeur du Corridor` (m) avec `CustomTextField`
    - `Nombre de passes` (1 ligne axiale, 2 lignes aller-retour, 3 lignes)
  - Adapter les paramètres de vol et de recouvrement associés.

#### [MODIFY] [home.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/layouts/home.dart)
- Mettre à jour `_buildMarkers` pour appeler soit `generateWaypoints` (Grille) soit `generateCorridorWaypoints` (Corridor).
- Mettre à jour l'outil de dessin cartographique pour supporter le tracé d'une polyligne linéaire ouverte en mode Corridor et afficher la ligne centrale ainsi que le polygone tampon enveloppant.

#### [MODIFY] [info.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/layouts/info.dart)
- Adapter les calculs du résumé de mission (Photos, Distance, Surface du corridor, Temps estimé) en fonction du mode actif.

#### [MODIFY] [export.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/layouts/export.dart) & [drone_mapper_format.dart](file:///d:/Nouveau%20dossier/DJI-Mapper-main/lib/core/drone_mapper_format.dart)
- Supporter l'importation KML de `<LineString>` / chemins linéaires pour charger directement la polyligne corridor.
- Exporter les waypoints corridor vers DJI Fly KMZ (WPML) et Litchi CSV.

---

## Verification Plan

### Automated Tests
- Exécuter la suite de tests avec `flutter test`.
- Ajouter des tests unitaires dédiés dans `test/corridor_engine_test.dart` vérifiant :
  - La génération des waypoints corridor (1 ligne, 2 lignes) selon le pas d'intervalle photo.
  - Le calcul du polygone tampon et de la surface du corridor.
  - L'exportation KMZ / KML d'une mission corridor.

### Manual Verification
- Basculer entre le mode Grille et le mode Corridor.
- Dessiner une polyligne sur la carte et modifier la largeur du corridor (ex. 20m $\to$ 80m).
- Vérifier la génération instantanée des waypoints et de la ligne de vol.
- Tester l'export KMZ et CSV.
