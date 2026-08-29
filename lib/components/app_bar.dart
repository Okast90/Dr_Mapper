import 'package:dji_mapper/components/popups/dji_load_alert.dart';
import 'package:dji_mapper/services/weather_service.dart';
import 'package:dji_mapper/shared/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'popups/litchi_load_alert.dart';

class MappingAppBar extends StatefulWidget implements PreferredSizeWidget {
  const MappingAppBar({super.key});

  @override
  State<MappingAppBar> createState() => _MappingAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MappingAppBarState extends State<MappingAppBar> {
  String _version = "";

  // État Météo & GPS
  bool _isLoadingWeather = true;
  double _windSpeedKmH = 0.0;
  double _temperatureC = 0.0;
  
  // Note: Le nombre de satellites GPS provient généralement du SDK Drone DJI
  // ou du plugin GPS natif de l'appareil.
  final int _satellitesCount = 16; 

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _fetchWeatherData();
  }

  Future<void> _loadAppVersion() async {
    final value = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = "V${value.version} (build ${value.buildNumber})";
    });
  }

  Future<void> _fetchWeatherData() async {
    setState(() => _isLoadingWeather = true);
    final data = await WeatherService.fetchRealtimeWeather();
    
    if (!mounted) return;
    setState(() {
      _windSpeedKmH = data.windSpeed;
      _temperatureC = data.temperature;
      _isLoadingWeather = false;
    });
  }

  void _showHelpDialog(Widget dialog) {
    showDialog(
      context: context,
      builder: (context) => dialog,
    );
  }

  void _showUserGuideDialog() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primaryContainer,
                        colorScheme.surfaceContainerHighest,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withOpacity(0.14),
                        ),
                        child: Icon(
                          Icons.help_center_rounded,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guide utilisateur',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Fonctionnalités et opérations disponibles',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHelpSection(
                          icon: Icons.map_rounded,
                          title: '1. Créer et modifier une zone de cartographie',
                          items: [
                            'Mode Grille (Surfacique) : tracez un polygone à partir de 3 sommets pour couvrir une parcelle ou un bâtiment.',
                            'Mode Corridor (Linéaire) : tracez une polyligne centrale pour les routes, cours d’eau, voies ferrées ou lignes électriques.',
                            'Mode Édition : déplacez les sommets, supprimez un point sélectionné ou effacez la zone.',
                            'Outils d’alignement : redressement et orthogonalisation automatique à angles droits (90°).',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.route_rounded,
                          title: '2. Génération et optimisation du plan de vol',
                          items: [
                            'Angle de balayage optimal (Auto) : détermine automatiquement l’orientation minimisant les virages et maximisant la batterie.',
                            'Décomposition convexe (Convex Split) : découpe les polygones en L, U ou étoile pour éliminer les trous dans les coins rentrants.',
                            'Buffer de bordure adaptatif (Border Margin) : maintient les centres caméras dans les limites tout en assurant une couverture complète.',
                            'Mode Corridor : réglez la largeur de bande tampon (10 à 1 000 m) et le nombre de passes (1 à 5 lignes de vol).',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.radar_rounded,
                          title: '3. Contrôle qualité et couverture photo',
                          items: [
                            'Ombres de couverture (Bouton Radar) : visualisez au sol l’empreinte physique réelle de chaque photo projetée selon le capteur et l’altitude.',
                            'Détection des trous : les zones sans recouvrement ou manquantes apparaissent immédiatement en transparence.',
                            'Indicateur de couverture % : badge interactif à côté de la recherche affichant en temps réel le pourcentage exact de zone couverte.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.camera_alt_rounded,
                          title: '4. Paramètres photo et capteurs',
                          items: [
                            'Ajustez les dimensions du capteur (mm), la focale (mm), la résolution (px) et l’angle gimbal.',
                            'Calcul automatique du GSD (Ground Sampling Distance) et de l’intervalle de déclenchement timelapse / hyperlapse.',
                            'Presets caméras pour les drones DJI (Mini, Mavic, Air, Matrice).',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.layers_rounded,
                          title: '5. Cartes, météo et import/export',
                          items: [
                            '3 couches de cartes disponibles : Google Plans, Google Satellite et OpenStreetMap (OSM).',
                            'Données météo (température, vitesse du vent) et satellites GPS en temps réel dans la barre supérieure.',
                            'Export aux formats DJI Fly / Pilot 2 (KMZ/WPML) et Litchi (CSV), avec import/export KML de contours et tracés.',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('J’ai compris'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHelpSection({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: colorScheme.primary.withOpacity(0.12),
                ),
                child: Icon(icon, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getGpsColor(int count) {
    if (count >= 12) return Colors.greenAccent;
    if (count >= 8) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Color _getWindColor(double wind) {
    if (wind < 20) return Colors.greenAccent;
    if (wind < 35) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Consumer<ThemeManager>(
      builder: (context, theme, child) => AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: isLight
                  ? [
                      const Color(0xFF0F4C81),
                      const Color(0xFF1976D2),
                      const Color(0xFF4FC3F7),
                    ]
                  : [
                      const Color(0xFF0F172A),
                      const Color(0xFF1D4ED8),
                      const Color(0xFF2563EB),
                    ],
            ),
          ),
        ),
        title: GestureDetector(
          onTap: () => showAboutDialog(
            context: context,
            applicationVersion: _version,
            applicationLegalese: "© 2024 Yaroslav Syubayev",
            applicationIcon: Image.asset(
              "assets/logo.png",
              width: 60,
            ),
          ),
          child: const Text(
            "YMapper",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        elevation: 0,
        actions: [
          // Widget météo en temps réel
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _isLoadingWeather
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Vent en temps réel
                      Tooltip(
                        message: "Vent en temps réel (cliquer pour rafraîchir)",
                        child: InkWell(
                          onTap: _fetchWeatherData,
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.air,
                                size: 18,
                                color: _getWindColor(_windSpeedKmH),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${_windSpeedKmH.toStringAsFixed(0)} km/h",
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Température en temps réel
                      Tooltip(
                        message: "Température extérieure",
                        child: Row(
                          children: [
                            const Icon(Icons.thermostat, size: 18),
                            const SizedBox(width: 2),
                            Text(
                              "${_temperatureC.toStringAsFixed(1)}°C",
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Satellites GPS
                      Tooltip(
                        message: "Satellites GPS connectés",
                        child: Row(
                          children: [
                            Icon(
                              Icons.satellite_alt,
                              size: 18,
                              color: _getGpsColor(_satellitesCount),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$_satellitesCount",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getGpsColor(_satellitesCount),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),

          const VerticalDivider(
            indent: 12,
            endIndent: 12,
            width: 16,
          ),

          // Bouton Mode Sombre / Clair
          IconButton(
            icon: Icon(
              isLight ? Icons.dark_mode : Icons.light_mode,
            ),
            tooltip: isLight ? "Passer en mode sombre" : "Passer en mode clair",
            onPressed: () => theme.toggleTheme(),
          ),

          // Menu déroulant
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            onSelected: (value) async {
              switch (value) {
                case "github":
                  await launchUrl(
                    Uri.https("github.com", "YLabs-FPV/YMapper"),
                  );
                  break;
                case "user_guide":
                  _showUserGuideDialog();
                  break;
                case "dji_help":
                  _showHelpDialog(const DjiLoadAlert(showCheckbox: false));
                  break;
                case "litchi_help":
                  _showHelpDialog(const LitchiLoadAlert(showCheckbox: false));
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: "github",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.open_in_browser),
                  title: Text("GitHub"),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: "user_guide",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.help_center_rounded),
                  title: Text("Guide utilisateur"),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  "Aide au chargement",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const PopupMenuItem(
                value: "dji_help",
                child: ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0),
                  leading: Icon(Icons.flight_takeoff),
                  title: Text("Mission DJI"),
                ),
              ),
              const PopupMenuItem(
                value: "litchi_help",
                child: ListTile(
                  contentPadding: EdgeInsets.only(left: 16.0),
                  leading: Icon(Icons.map),
                  title: Text("Mission Litchi"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}