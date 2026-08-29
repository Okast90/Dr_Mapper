# Contrôle Qualité de Couverture Photo (Ombre / Empreintes au Sol)

## Modifications apportées

### 1. Moteur de Calcul d'Empreinte Photo au Sol (`DroneMappingEngine`)
- **Méthode `generatePhotoFootprints(List<LatLng> photoLocations)`** :
  - Calcule l'empreinte physique réelle de chaque cliché au sol ($L \times l$) en fonction de :
    - L'altitude de vol effective ($Alt - Offset$).
    - La taille du capteur (largeur et hauteur en mm).
    - La focale de l'objectif (mm).
    - La résolution en pixels de l'image (GSD $X$ et $Y$).
    - L'orientation / angle de rotation de la mission ($\theta$).
  - Produit un polygone rectangulaire géoréférencé à 4 sommets pour chaque point de prise de vue.

### 2. Affichage Visuel "Ombre de Couverture" (Contrôle Qualité Anti-Trous)
- **Superposition translucide multi-couches** :
  - Chaque photo projette son ombre/empreinte translucide sur la carte.
  - Les zones avec recouvrement (overlap & sidelap) se superposent naturellement pour créer une teinte plus dense.
  - Tout **trou de couverture** ou zone omise apparaît immédiatement sous forme d'espace clair/transparent non couvert.

### 3. Bouton Dédié de Contrôle Qualité (Toolbar)
- **Emplacement & Style** :
  - Intégré dans la barre d'outils flottante juste avant la barre de recherche.
  - Reprend exactement le design system, les micro-animations et les états `selected` (`_mapActionButton`) des boutons voisins.
  - Icône radar / scanner (`Icons.radar_rounded`) avec infobulle interactive et notification dynamique à l'activation / désactivation.

## Tests et Validation
- **Tests unitaires** : `10/10 tests passés` (`flutter test`), incluant la validation géométrique des empreintes 4 coins (`generatePhotoFootprints`).
