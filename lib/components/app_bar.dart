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
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primaryContainer.withAlpha(220),
                        colorScheme.surfaceContainerHighest.withAlpha(240),
                      ],
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withAlpha(120),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withAlpha(35),
                          border: Border.all(
                            color: colorScheme.primary.withAlpha(80),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.menu_book_rounded,
                          color: colorScheme.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guide Utilisateur DJI-Mapper',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Manuel interactif des fonctionnalités et flux de travail',
                              style: TextStyle(
                                fontSize: 13,
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
                          icon: Icons.timeline_rounded,
                          accentColor: colorScheme.primary,
                          title: '1. Import GPX & 3 Modes de Plan de Vol',
                          items: [
                            'Import GPX : Importez facilement des traces (<trk>), routes (<rte>) ou waypoints (<wpt>) par bouton ou glisser-déposer.',
                            'Mode Suivi Direct : Le drone survole fidèlement chaque point du GPX avec déclenchement photo et délai personnalisable.',
                            'Mode Corridor Linéaire : La trace sert d\'axe central pour générer un couloir de vol avec largeur réglable (10 à 1 000 m) et 1 à 5 passes.',
                            'Mode Zone / Polygone : Balayage photogrammétrique optimisé en surface (grille fermée).',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.auto_awesome_rounded,
                          accentColor: colorScheme.secondary,
                          title: '2. Moteur d’Optimisation Géométrique',
                          items: [
                            'Balayage Optimal Automatique : Calcule l\'angle de vol idéal pour minimiser les virages et économiser la batterie.',
                            'Décomposition Convexe (Convex Split) : Découpe les formes complexes (en L, U, étoile) pour éliminer les angles morts.',
                            'Buffer de Bordure Adaptatif (Margin Inset) : Garde le drone à l\'intérieur de la zone tout en assurant une couverture photo complète des bords.',
                            'Outils Géométriques : Auto-réparation, redressement, orthogonalisation à 90° et simplification du contour.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.radar_rounded,
                          accentColor: colorScheme.tertiary,
                          title: '3. Contrôle Qualité (QC) & Télémétrie',
                          items: [
                            'Ombres de Couverture (Bouton Radar) : Affiche l\'empreinte physique réelle de chaque photo au sol.',
                            'Badge de Couverture % en Direct : Indicateur interactif mesurant en continu le pourcentage exact de zone cartographiée.',
                            'Télémétrie & Métriques : Estimation du temps de vol total, de la distance parcourue, de la consommation de batterie et du nombre de clichés.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.camera_alt_rounded,
                          accentColor: Colors.teal,
                          title: '4. Capteurs, Focales & Météo en Direct',
                          items: [
                            'Presets Drones DJI intégrés : DJI Mini, Mavic, Air, Phantom, Inspire et Matrice.',
                            'Calcul instantané du GSD (Ground Sampling Distance en cm/px) et de la vitesse d\'obturation recommandée pour éviter le flou.',
                            'Météo Temps Réel : Affichage dynamique de la vitesse du vent et de la température via Open-Meteo.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.file_download_rounded,
                          accentColor: Colors.deepPurple,
                          title: '5. Exports Prêts pour le Vol (DJI Fly & Litchi)',
                          items: [
                            'DJI Fly & DJI Pilot 2 : Export d\'archive KMZ standard contenant template.kml et waylines.wpml (chargement direct sur radiocommande).',
                            'Litchi : Export de missions complètes en CSV avec altitudes, vitesses et actions de nacelle/caméra.',
                            'KML : Export et ré-import des polygones et axes pour échange avec QGIS, Google Earth ou autres SIG.',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Fermer le guide', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
    Color? accentColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final primaryAccent = accentColor ?? colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryAccent.withAlpha(45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withAlpha(8),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: primaryAccent.withAlpha(28),
                ),
                child: Icon(icon, color: primaryAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
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
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    size: 17,
                    color: primaryAccent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.45,
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