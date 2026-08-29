# 🛸 Architecture & Guide Technique Exhaustif — DJI Mapper

Ce document constitue la **documentation technique complète** du projet **DJI Mapper**. Il détaille l'architecture globale, le rôle de chaque dossier et fichier, les fonctions clés avec des exemples de code, les algorithmes mathématiques de photogrammétrie, ainsi qu'un guide pratique pour maintenir et étendre le code.

---

## 📑 Table des Matières

1. [Vue d'ensemble du Projet](#1-vue-densemble-du-projet)
2. [Arborescence Complète du Projet](#2-arborescence-complète-du-projet)
3. [Analyse Détaillée Dossier par Dossier & Fichier par Fichier](#3-analyse-détaillée-dossier-par-dossier--fichier-par-fichier)
   - [3.1 Point d'Entrée & Initialisation (`lib/main.dart`)](#31-point-dentrée--initialisation-libmaindart)
   - [3.2 Moteur Algorithmique & Formats (`lib/core/`)](#32-moteur-algorithmique--formats-libcore)
   - [3.3 Écrans & Vues Principales (`lib/layouts/`)](#33-écrans--vues-principales-liblayouts)
   - [3.4 Composants Graphiques & Dialogues (`lib/components/`)](#34-composants-graphiques--dialogues-libcomponents)
   - [3.5 Services & Connecteurs Externes (`lib/services/` & `lib/github/`)](#35-services--connecteurs-externes-libservices--libgithub)
   - [3.6 Gestion d'État Global & Modèles (`lib/shared/`)](#36-gestion-détat-global--modèles-libshared)
   - [3.7 Presets Caméras & Drones (`lib/presets/`)](#37-presets-caméras--drones-libpresets)
4. [Moteur de Photogrammétrie & Algorithmes Mathématiques](#4-moteur-de-photogrammétrie--algorithmes-mathématiques)
   - [4.1 Formules de GSD & Empreintes Photo au Sol](#41-formules-de-gsd--empreintes-photo-au-sol)
   - [4.2 Balayage Boustrophédon (Mode Grille)](#42-balayage-boustrophédon-mode-grille)
   - [4.3 Angle de Balayage Optimal (Optimal Sweep Angle)](#43-angle-de-balayage-optimal-optimal-sweep-angle)
   - [4.4 Buffer de Bordure Adaptatif (Margin Inset)](#44-buffer-de-bordure-adaptatif-margin-inset)
   - [4.5 Décomposition Convexe (Ear-Clipping & Hertel-Mehlhorn)](#45-décomposition-convexe-ear-clipping--hertel-mehlhorn)
   - [4.6 Mode Corridor (Photogrammétrie Linéaire)](#46-mode-corridor-photogrammétrie-linéaire)
   - [4.7 Calcul Précis du % de Couverture & Remplissage Résiduel](#47-calcul-précis-du--de-couverture--remplissage-résiduel)
5. [Flux de Données & Gestion d'État (State Management)](#5-flux-de-données--gestion-détat-state-management)
6. [Guide Pratique Développeur : « Où et Comment Modifier ? »](#6-guide-pratique-développeur--où-et-comment-modifier-)
   - [Cas 1 : Ajouter un nouveau preset de drone / caméra](#cas-1--ajouter-un-nouveau-preset-de-drone--caméra)
   - [Cas 2 : Ajouter un nouveau paramètre de vol](#cas-2--ajouter-un-nouveau-paramètre-de-vol)
   - [Cas 3 : Ajouter un nouveau format d'export de mission](#cas-3--ajouter-un-nouveau-format-dexport-de-mission)
   - [Cas 4 : Ajouter un bouton ou un outil sur la carte](#cas-4--ajouter-un-bouton-ou-un-outil-sur-la-carte)
   - [Cas 5 : Ajouter une nouvelle couche de carte (Map Layer)](#cas-5--ajouter-une-nouvelle-couche-de-carte-map-layer)
7. [Tests Unitaires & Validation (`test/`)](#7-tests-unitaires--validation-test)
8. [Commandes de Compilation & Déploiement](#8-commandes-de-compilation--déploiement)

---

## 1. Vue d'ensemble du Projet

**DJI Mapper** est une application multiplateforme (Desktop Windows/Linux/macOS, Web, Android) conçue avec **Flutter & Dart**. Elle permet aux télépilotes professionnels et géomètres de planifier des missions de cartographie aérienne et d'inspection :
- **Mode Grille Surfacique (2D/3D)** : pour couvrir des parcelles, bâtiments, champs et carrières.
- **Mode Corridor Linéaire** : pour balayer des infrastructures longilignes (routes, voies ferrées, lignes électriques, cours d'eau, clôtures).
- **Contrôle Qualité Visuel (QC)** : affichage de l'ombre physique des photos projetée au sol pour déceler instantanément les trous de couverture.
- **Indicateur de Couverture en Temps Réel** : calcul précis du ratio de surface couverte ($\%$).
- **Exports Multi-Formats** : archives DJI Fly / Pilot 2 (`KMZ` contenant `template.kml` et `waylines.wpml`), fichiers Litchi (`CSV`), et polygones/trajectoires `KML`.

---

## 2. Arborescence Complète du Projet

```text
DJI-Mapper-main/
├── lib/                               # Code source principal de l'application
│   ├── main.dart                      # Point d'entrée de l'application Flutter
│   ├── components/                    # Composants d'interface réutilisables
│   │   ├── app_bar.dart               # Barre supérieure (météo, GPS, aide/guide, thème)
│   │   ├── text_field.dart            # Champ de saisie numérique stylisé avec unités
│   │   └── popups/                    # Fenêtres modales d'information
│   │       ├── dji_load_alert.dart    # Instructions de chargement sur DJI Fly/Pilot
│   │       └── litchi_load_alert.dart # Instructions de chargement sur Litchi
│   ├── core/                          # Moteur mathématique et géométrique pur
│   │   ├── drone_mapping_engine.dart  # Calculs de waypoints, footprints, décomposition, angles
│   │   └── drone_mapper_format.dart   # Parsing et conversion KML/GeoXML
│   ├── layouts/                       # Vues et panneaux de l'interface utilisateur
│   │   ├── home.dart                  # Écran principal avec carte Leaflet/FlutterMap & toolbar
│   │   ├── aircraft.dart              # Paramètres aéronef, vitesse, modes et optimisation
│   │   ├── camera.dart                # Paramètres capteur, focale, résolution et presets
│   │   ├── info.dart                  # Métriques de mission (temps, photos, surface, GSD)
│   │   └── export.dart                # Écran d'import/export (KML, KMZ, Litchi CSV)
│   ├── presets/                       # Profils de capteurs pré-enregistrés
│   │   ├── camera_preset.dart         # Modèle de données d'un profil caméra
│   │   └── preset_manager.dart        # Base de données des drones DJI (Mini, Mavic, Air, Matrice)
│   ├── services/                      # Services I/O et fonctionnalités externes
│   │   ├── kmz_exporter.dart          # Générateur d'archives ZIP/KMZ compatibles DJI WPML
│   │   └── weather_service.dart       # Récupération de la météo temps réel (Open-Meteo API)
│   ├── shared/                        # Gestion d'état global et persistance locale
│   │   ├── value_listeneables.dart    # Modèle d'état réactif central (ChangeNotifier)
│   │   ├── theme_manager.dart         # Gestion du thème Sombre / Clair
│   │   ├── map_provider.dart          # Contrôleur global de la carte FlutterMap
│   │   └── aircraft_settings.dart     # Persistance des réglages via SharedPreferences
│   └── github/                        # Utilitaires de mise à jour
│       └── update_checker.dart        # Vérification des nouvelles versions GitHub Releases
├── test/                              # Suite de tests unitaires et d'intégration
│   ├── corridor_engine_test.dart      # Tests du mode corridor, calculs de longueur et passes
│   ├── kmz_exporter_test.dart         # Tests de génération des archives KMZ / WPML
│   └── polygon_optimization_test.dart # Tests des 4 algorithmes d'optimisation géométrique
├── web/                               # Configuration et assets pour le déploiement Web
├── assets/                            # Icônes et polices vectorielles
├── pubspec.yaml                       # Dépendances Flutter et métadonnées du projet
├── README.md                          # Présentation générale du dépôt
└── GUIDE_TECHNIQUE_ET_ARCHITECTURE.md # Ce document technique exhaustif
```

---

## 3. Analyse Détaillée Dossier par Dossier & Fichier par Fichier

### 3.1 Point d'Entrée & Initialisation (`lib/main.dart`)
- **Rôle** : Configure l'application Flutter, injecte les `ChangeNotifierProvider` pour l'état global, applique les thèmes clairs/sombres, et initialise la fenêtre sur Desktop via `window_manager`.
- **Composants clés** :
  - `MultiProvider` : Fournit `ValueListenables`, `ThemeManager`, et `MapProvider` à l'arbre complet des widgets.
  - `ThemeManager` : Écoute les changements de mode sombre/clair et adapte la palette Material 3.
  - `HomeLayout` : Définit la vue racine.

```dart
// Extrait de lib/main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ValueListenables()),
        ChangeNotifierProvider(create: (_) => ThemeManager()),
        ChangeNotifierProvider(create: (_) => MapProvider()),
      ],
      child: const MainApp(),
    ),
  );
}
```

---

### 3.2 Moteur Algorithmique & Formats (`lib/core/`)

#### `lib/core/drone_mapping_engine.dart`
C'est le **cœur scientifique et géométrique** de tout le projet (1 300+ lignes). Il est exempt de toute dépendance à l'UI Flutter, ce qui le rend ultra-rapide et 100% testable unitairement.

- **Attributs clés** :
  - `altitude`, `forwardOverlap`, `sideOverlap`, `sensorWidth`, `sensorHeight`, `focalLength`, `imageWidth`, `imageHeight`, `angle`, `groundOffset`.
- **Propriétés calculées** :
  - `gsdX`, `gsdY` : Résolution au sol en cm/pixel.
  - `footprintWidth`, `footprintHeight` : Dimensions réelles du cliché au sol en mètres.
  - `horizontalLineSpacing`, `horizontalWaypointSpacing` : Interlignes et inter-points tenant compte du recouvrement.
- **Fonctions principales** :
  1. `generateWaypoints(polygon, createCameraPoints, fillGrid, homePoint, useInsetBuffer, useConvexDecomposition)` :
     Génère le parcours complet en grille ou décomposition convexe.
  2. `_findOptimalSweepAngle(polygon)` :
     Teste 36 orientations ($0^\circ$ à $175^\circ$) et choisit l'angle minimisant le nombre de virages.
  3. `_insetPolygon(polygon, insetDist)` :
     Applique une érosion normale (*negative buffer*) sur la bordure.
  4. `_isConvexPolygon(poly)`, `_earClip(poly)`, `_hertelMehlhorn(poly, triangles)` :
     Décompose les polygones concaves en sous-polygones convexes indépendants.
  5. `generateCorridorBufferPolygon(centerline, width)` & `generateCorridorWaypoints(...)` :
     Génère le polygone tampon et les lignes de vol multi-passes (1 à 5 lignes) le long d'une polyligne.
  6. `generatePhotoFootprints(photoLocations)` :
     Calcule les 4 sommets géographiques du polygone de chaque cliché pour le contrôle qualité.
  7. `calculateCoveragePercentage(polygon, photoLocations)` :
     Calcule le pourcentage exact de zone couverte par échantillonnage surfacique.
  8. `generateResidualFillWaypoints(...)` :
     Détecte et génère des waypoints de remplissage sur les îlots non couverts.

#### `lib/core/drone_mapper_format.dart`
- **Rôle** : Parse et sérialise les fichiers KML standard à l'aide du package `geoxml`.
- **Fonctions clés** :
  - `loadKml(String content)` : Extrait les polygones (`kml.polygons`), les routes (`kml.rtes`), les tracés (`kml.trks`) et les waypoints (`kml.wpts`).
  - `exportKml(List<LatLng> polygon, List<LatLng> waypoints)` : Génère un document KML valide contenant la zone et les points de vol.

---

### 3.3 Écrans & Vues Principales (`lib/layouts/`)

#### `lib/layouts/home.dart`
- **Rôle** : L'écran principal de l'application. Gère la carte interactive (`FlutterMap`), le panneau latéral accordéon, la barre d'outils flottante et la barre de recherche.
- **Fonctionnalités clés** :
  - **Couches cartographiques** : Support de `MapLayer.streets` (Google Plans), `MapLayer.satellite` (Google Satellite) et `MapLayer.openStreetMap` (TileLayer OSM avec filtre dark mode).
  - **Barre d'outils cartographique (`_mapActionButton`)** :
    - Mode Tracé polygone / polyligne.
    - Mode Édition / Déplacement des sommets.
    - Alignement rectiligne & Orthogonalisation à 90°.
    - **Bouton Radar de Contrôle Qualité (QC)** : Active/désactive la couche des ombres de couverture.
    - Effacement complet du polygone / corridor.
  - **Recherche de lieu** : Autocomplete OpenStreetMap Nominatim géocodé.
  - **Badge de Couverture $\%$** : Affiche le pourcentage de surface couverte calculé en temps réel juste à côté de la recherche.

#### `lib/layouts/aircraft.dart`
- **Rôle** : Panneau de configuration du vol et de l'aéronef.
- **Sections** :
  - *Survey Mode* : Sélecteur visuel entre **Grid (Area)** et **Corridor (Linear)**.
  - *Flight Parameters* : Altitude (100–5 000 m), Ground Offset, Vitesse (m/s), Délai par waypoint.
  - *Corridor Parameters* (si mode Corridor) : Largeur tampon (10–1 000 m), Sélecteur de passes (1, 2, 3, 4, 5 lignes).
  - *Mapping Coverage* (si mode Grille) : Recouvrement frontal (Overlap), latéral (Sidelap), Slider de rotation (avec affichage `Auto (Optimal)` à 0°), et toggles d'optimisation géométrique (`Convex Split` et `Border Margin`).
  - *Actions & Safety* : Comportement en fin de mission (Hover, RTH, Land) et perte RC.

#### `lib/layouts/camera.dart`
- **Rôle** : Panneau de réglage du capteur et de la caméra.
- **Fonctionnalités** :
  - Sélection de profils pré-enregistrés (DJI Mini 4 Pro, Mavic 3 Enterprise, etc.).
  - Saisie manuelle de la largeur/hauteur capteur, longueur focale et résolution pixels.
  - Sauvegarde de presets personnalisés dans les préférences locales.

#### `lib/layouts/info.dart`
- **Rôle** : Tableau de bord des statistiques de mission en temps réel.
- **Métriques calculées** :
  - Surface totale ($m^2$ ou $ha$) ou Longueur du corridor ($m$ / $km$).
  - Nombre de photos à capturer et nombre total de waypoints.
  - Distance totale de vol estimée et durée de mission (avec alertes de batterie si > 25 min).
  - GSD (Ground Sample Distance en $cm/px$) et vitesse d'obturation recommandée pour éviter le flou de bougé.

#### `lib/layouts/export.dart`
- **Rôle** : Hub d'exportation et d'importation de missions.
- **Options d'export** :
  - **DJI Fly / Pilot 2 (KMZ / WPML)** : Archive compressée directement injectable dans la radiocommande DJI (RC 2, RC Pro, etc.).
  - **Litchi (CSV)** : Fichier CSV pour les drones compatibles SDK v4.
  - **KML** : Export de la zone géoréférencée pour Google Earth, QGIS ou ArcGIS.

---

### 3.4 Composants Graphiques & Dialogues (`lib/components/`)

- `lib/components/app_bar.dart` :
  Barre supérieure intégrant les données météo en temps réel (vitesse du vent en km/h, température via Open-Meteo), le statut des satellites GPS, le sélecteur de thème Sombre/Clair, et le dialogue interactif **Guide utilisateur**.
- `lib/components/text_field.dart` :
  Widget `CustomTextField` fournissant des champs de saisie numérique fiables avec boutons d'incrémentation/décrémentation, validation de plage `[min, max]`, et gestion des décimales.
- `lib/components/popups/dji_load_alert.dart` & `litchi_load_alert.dart` :
  Modales didactiques expliquant pas-à-pas à l'utilisateur où copier le fichier `.kmz` ou `.csv` sur sa radiocommande ou son smartphone.

---

### 3.5 Services & Connecteurs Externes (`lib/services/` & `lib/github/`)

- `lib/services/kmz_exporter.dart` :
  Construit en mémoire l'archive `.kmz` conforme au standard DJI WPML :
  - `wpmz/template.kml` : Métadonnées générales, configuration du drone et modèle de capteur.
  - `wpmz/waylines.wpml` : Liste précise des waypoints avec coordonnées latitude/longitude/altitude ellipsoïdale, vitesse, actions de déclenchement photo et orientations gimbal.
- `lib/services/weather_service.dart` :
  Interroge l'API REST publique Open-Meteo pour obtenir les conditions anémométriques et thermiques locales sans nécessiter de clé API.
- `lib/github/update_checker.dart` :
  Consulte l'API GitHub Releases pour notifier l'utilisateur si une mise à jour de DJI Mapper est disponible.

---

### 3.6 Gestion d'État Global & Modèles (`lib/shared/`)

- `lib/shared/value_listeneables.dart` :
  La classe `ValueListenables` hérite de `ChangeNotifier`. Elle centralise l'intégralité des variables de configuration et de l'état de l'application :
  - Mode de cartographie (`mappingMode` : `grid` ou `corridor`).
  - Géométries : `polygon`, `centerline`, `photoLocations`, `homePoint`, `flightLine`, `takeoffLine`, `returnLine`.
  - Paramètres de vol : `altitude`, `speed`, `forwardOverlap`, `sideOverlap`, `rotation`, `useInsetBuffer`, `useConvexDecomposition`, etc.
- `lib/shared/theme_manager.dart` :
  Bascule le `ThemeMode` (`light` / `dark`) et persiste le choix dans `SharedPreferences`.
- `lib/shared/map_provider.dart` :
  Fournit une instance singleton de `MapController` pour permettre de déplacer ou zoomer la carte depuis n'importe quel widget.
- `lib/shared/aircraft_settings.dart` :
  Modèle de sérialisation JSON pour sauvegarder et restaurer les préférences de vol.

---

### 3.7 Presets Caméras & Drones (`lib/presets/`)

- `lib/presets/camera_preset.dart` :
  Définit la structure d'une caméra : `name`, `sensorWidth`, `sensorHeight`, `focalLength`, `imageWidth`, `imageHeight`.
- `lib/presets/preset_manager.dart` :
  Contient la liste des profils d'usine (DJI Mini 2, Mini 3 Pro, Mini 4 Pro, Mavic 3 Classic/Pro/Enterprise, Air 2S, Air 3, Phantom 4 Pro, Matrice 300/350 P1, etc.) et gère l'ajout/suppression de presets personnalisés par l'utilisateur.

---

## 4. Moteur de Photogrammétrie & Algorithmes Mathématiques

### 4.1 Formules de GSD & Empreintes Photo au Sol

Pour un drone volant à une altitude relative $H$ ($H = Altitude - GroundOffset$), avec un capteur de largeur $S_w$ (mm), hauteur $S_h$ (mm), une focale $F$ (mm) et une image de dimensions $I_w \times I_h$ (pixels) :

$$\text{GSD}_x = \frac{H \times S_w}{I_w \times F}, \quad \text{GSD}_y = \frac{H \times S_h}{I_h \times F} \quad (\text{en mètres/pixel})$$

L'empreinte réelle de la photo au sol ($W \times H$) est :
$$W = \text{GSD}_x \times I_w = \frac{H \times S_w}{F}, \quad H = \text{GSD}_y \times I_h = \frac{H \times S_h}{F}$$

En appliquant le recouvrement frontal ($O_f$) et latéral ($O_s$) :
$$\text{Interligne (Cross-track)} = W \times (1 - O_s)$$
$$\text{Intervalle entre photos (Along-track)} = H \times (1 - O_f)$$

---

### 4.2 Balayage Boustrophédon (Mode Grille)

Le balayage génère une trajectoire en serpentin (*boustrophedon*) :
1. Le polygone GPS est projeté en coordonnées cartésiennes locales métriques $(X, Y)$ avec l'origine au premier point.
2. Le polygone est tourné de l'angle de vol $\theta$.
3. Une grille de lignes horizontales espacées de $\text{Interligne}$ balaie la boîte englobante.
4. Les intersections avec le polygone sont calculées, et les segments sont alternés (gauche $\rightarrow$ droite puis droite $\rightarrow$ gauche).
5. Les points sont ensuite dé-tournés ($-\theta$) et reconvertis en coordonnées géographiques `LatLng`.

---

### 4.3 Angle de Balayage Optimal (Optimal Sweep Angle)

Dans `lib/core/drone_mapping_engine.dart`, la méthode `_findOptimalSweepAngle(List<Point> polygon)` teste 36 orientations de $0^\circ$ à $175^\circ$ par pas de $5^\circ$. Pour chaque angle, elle calcule le nombre de lignes de balayage nécessaires pour couvrir le polygone. L'angle minimisant ce nombre est retenu :
- **Bénéfice** : Moins de virages à $180^\circ$, trajectoires plus longues et gain d'autonomie de batterie pouvant atteindre 20 à 35%.

```dart
// Extrait de lib/core/drone_mapping_engine.dart
static double _findOptimalSweepAngle(List<Point> polygon, {int angleStepDeg = 5}) {
  if (polygon.length < 3) return 0.0;
  double bestAngle = 0.0;
  int bestLines = 0x7fffffff;

  for (int deg = 0; deg < 180; deg += angleStepDeg) {
    final rad = deg * pi / 180.0;
    final rotated = _rotatePolygon(polygon, deg.toDouble());
    // Comptage des lignes traversant le polygone...
    if (lineCount < bestLines) {
      bestLines = lineCount;
      bestAngle = deg.toDouble();
    }
  }
  return bestAngle;
}
```

---

### 4.4 Buffer de Bordure Adaptatif (Margin Inset)

La méthode `_insetPolygon(List<Point> polygon, double insetDist)` applique un retrait négatif vers l'intérieur :
- Déplace chaque segment vers l'intérieur selon son vecteur normal unitaire.
- Recalcule les sommets par intersection des droites décalées.
- Intègre des sécurités contre l'auto-intersection ou l'inversion géométrique sur les petits polygones.
- **Bénéfice** : Les centres des caméras restent dans le périmètre autorisé tout en assurant que le cône de vue extérieur ($Footprint / 2$) couvre parfaitement la limite du terrain.

---

### 4.5 Décomposition Convexe (Ear-Clipping & Hertel-Mehlhorn)

Pour les formes concaves (polygones en **L**, **U**, ou **étoile**), un balayage global unique crée des segments morts hors zone et des trous de couverture dans les coins rentrants.
1. `_earClip` : Triangule le polygone concave en $O(n^2)$ en coupant successivement les « oreilles » convexes sans sommet intérieur.
2. `_hertelMehlhorn` : Fusionne de manière gloutonne les triangles adjacents partageant une arête tant que le polygone résultant reste strictement convexe.
3. Chaque sous-polygone convexe est balayé avec sa propre orientation optimale, puis les waypoints sont connectés en une mission unifiée continue.

---

### 4.6 Mode Corridor (Photogrammétrie Linéaire)

Développé pour les infrastructures longilignes :
1. `generateCorridorBufferPolygon` : Calcule les vecteurs normaux de chaque segment de la polyligne centrale pour créer un polygone tampon de largeur $W$ ($halfWidth = W / 2$).
2. `generateCorridorWaypoints` : Détermine les lignes décalées selon le nombre de passes demandé :
   - **1 ligne** : vol direct sur la ligne centrale.
   - **2 lignes** : passes décalées à $-W/4$ et $+W/4$.
   - **$N$ lignes** : répartition équidistante de $-W/2$ à $+W/2$ avec inversion alternée du sens de vol.

```dart
// Extrait de lib/core/drone_mapping_engine.dart
final offsetDistances = <double>[];
if (flightLines <= 1) {
  offsetDistances.add(0.0);
} else if (flightLines == 2) {
  offsetDistances.add(-corridorWidth / 4.0);
  offsetDistances.add(corridorWidth / 4.0);
} else {
  final step = corridorWidth / (flightLines - 1);
  for (int i = 0; i < flightLines; i++) {
    offsetDistances.add(-corridorWidth / 2.0 + i * step);
  }
}
```

---

### 4.7 Calcul Précis du % de Couverture & Remplissage Résiduel

La méthode `calculateCoveragePercentage` échantillonne l'intérieur du polygone sur une grille fine ($30 \times 30$). Pour chaque cellule intérieure, elle teste géométriquement si le point se trouve dans le rectangle orienté d'au moins un cliché photo :

$$\text{Couverture } (\%) = \frac{\text{Nombre de cellules couvertes}}{\text{Nombre total de cellules intérieures}} \times 100\%$$

La méthode `generateResidualFillWaypoints` isole les cellules où `covered == false` et génère automatiquement des waypoints de comblement ciblés.

---

## 5. Flux de Données & Gestion d'État (State Management)

L'architecture repose sur le pattern **Provider + ChangeNotifier** :

```text
┌────────────────────────────────────────────────────────┐
│                   ValueListenables                     │
│  (polygon, centerline, altitude, speed, overlap, etc.) │
└──────────────────────────┬─────────────────────────────┘
                           │ notifyListeners()
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  HomeLayout   │  │ AircraftBar   │  │    InfoBar    │
│  (FlutterMap, │  │ (Sliders,     │  │ (Temps, GSD,  │
│   Toolbar,    │  │  Modes,       │  │  Photos,      │
│   QC Shadows) │  │  Toggles)     │  │  Distance)    │
└───────────────┘  └───────────────┘  └───────────────┘
```

1. Lorsque l'utilisateur modifie un paramètre dans l'interface (ex: altitude, mode corridor, déplacement d'un point sur la carte), le setter correspondant dans `ValueListenables` est appelé.
2. `ValueListenables` invoque `notifyListeners()`.
3. `HomeLayout` détecte la mise à jour via `_refreshMissionVisuals(listenables)` en comparant une signature d'état (`_lastMissionVisualSignature`).
4. Si la signature a changé, `_buildMarkers` régénère les waypoints, les empreintes photo au sol, et recalcule le pourcentage de couverture instantanément.

---

## 6. Guide Pratique Développeur : « Où et Comment Modifier ? »

### Cas 1 : Ajouter un nouveau preset de drone / caméra
- **Fichier à modifier** : `lib/presets/preset_manager.dart`
- **Procédure** : Ajoutez une nouvelle entrée dans la liste `_defaultPresets` :
```dart
CameraPreset(
  name: "DJI Mavic 4 Pro",
  sensorWidth: 17.3,
  sensorHeight: 13.0,
  focalLength: 12.0,
  imageWidth: 5280,
  imageHeight: 3956,
)
```

---

### Cas 2 : Ajouter un nouveau paramètre de vol
1. **Dans `lib/shared/value_listeneables.dart`** :
   Déclarez le `ValueNotifier` et son getter/setter :
   ```dart
   final _gimbalPitch = ValueNotifier<double>(-90.0);
   double get gimbalPitch => _gimbalPitch.value;
   set gimbalPitch(double value) {
     _gimbalPitch.value = value;
     notifyListeners();
   }
   ```
2. **Dans `lib/layouts/aircraft.dart`** :
   Ajoutez le contrôle graphique (Slider ou `CustomTextField`) lié à `listenables.gimbalPitch`.
3. **Dans `lib/core/drone_mapping_engine.dart`** :
   Utilisez la nouvelle variable dans la génération de waypoints ou les calculs de mission.

---

### Cas 3 : Ajouter un nouveau format d'export de mission
1. **Dans `lib/services/`** :
   Créez votre classe de sérialisation (ex: `lib/services/qgc_plan_exporter.dart`).
2. **Dans `lib/layouts/export.dart`** :
   Ajoutez un bouton dans `_buildExportSection` appelant votre exportateur et déclenchant le téléchargement du fichier via `PlatformExport.saveFile`.

---

### Cas 4 : Ajouter un bouton ou un outil sur la carte
- **Fichier à modifier** : `lib/layouts/home.dart`
- **Procédure** : Localisez la barre d'outils flottante dans la méthode `build` (autour des lignes 1100–1200) et ajoutez un widget `_mapActionButton` :
```dart
_mapActionButton(
  icon: Icons.my_new_tool_rounded,
  tooltip: 'Mon nouvel outil',
  selected: _myToolActive,
  onPressed: () {
    setState(() {
      _myToolActive = !_myToolActive;
    });
  },
),
```

---

### Cas 5 : Ajouter une nouvelle couche de carte (Map Layer)
1. **Dans `lib/layouts/home.dart`** :
   - Ajoutez la valeur dans l'enum `enum MapLayer { streets, satellite, openStreetMap, topographique }`.
   - Mettez à jour `_getMapLayerName`.
   - Dans le `TileLayer` du widget `FlutterMap`, ajoutez l'URL template correspondant (ex: OpenTopoMap, Mapbox, ESRI) :
   ```dart
   urlTemplate: _selectedMapLayer == MapLayer.topographique
       ? 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png'
       : ...
   ```

---

## 7. Tests Unitaires & Validation (`test/`)

Le projet dispose d'une suite complète de **15 tests unitaires** couvrant l'intégralité de la logique géométrique et des exports :

1. `test/corridor_engine_test.dart` :
   - Calcul de longueur de polyligne géodésique (Haversine).
   - Calcul de surface de corridor.
   - Génération de polygone tampon fermé.
   - Génération des trajectoires 1-passe et multi-passes.
   - Génération des empreintes 4-coins au sol.
2. `test/kmz_exporter_test.dart` :
   - Création d'archives KMZ conformes DJI avec `template.kml` et `waylines.wpml`.
   - Normalisation et persistance des coordonnées géographiques.
   - Scénarios de robustesse aux listes vides.
3. `test/polygon_optimization_test.dart` :
   - Décomposition convexe sur formes en L et concaves.
   - Génération de waypoints sur polygones convexes réguliers.
   - Calcul précis du pourcentage de couverture ($0\%$ à $100\%$).
   - Remplissage des trous résiduels (*Residual Gap Fill*).

### Exécuter les tests :
```bash
flutter test
```

---

## 8. Commandes de Compilation & Déploiement

### Dépendances :
```bash
flutter pub get
```

### Exécution en mode développement :
```bash
flutter run
```

### Compilation Web de Production :
```bash
flutter build web --no-wasm-dry-run
```
*(Les fichiers prêts pour la production sont générés dans le dossier `build/web/`)*

### Compilation Desktop :
```bash
# Windows
flutter build windows --release

# Linux
flutter build linux --release

# macOS
flutter build macos --release
```

### Déploiement Docker (Web Nginx) :
```bash
docker-compose up -d --build
```
L'application est immédiatement accessible sur `http://localhost:8090`.
