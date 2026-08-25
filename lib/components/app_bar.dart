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
                            'Activez le mode de dessin pour tracer le contour directement sur la carte.',
                            'Le contour est immédiatement exploitable dès qu’il contient au moins 3 points, sans importer un KML.',
                            'Utilisez le mode édition pour déplacer les points, supprimer un point sélectionné, valider le contour ou corriger sa géométrie.',
                            'Les outils d’alignement permettent d’obtenir un polygone plus régulier, droit ou orthogonal avec des angles à 90°.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.route_rounded,
                          title: '2. Générer le plan de vol',
                          items: [
                            'Une fois la zone validée, l’application génère automatiquement les points de passage de la mission.',
                            'Vous pouvez ajuster l’altitude, la vitesse, la rotation, le recouvrement, le point d’origine et le décalage du sol.',
                            'Les lignes de vol, la trajectoire de retour et les points de prise de vue peuvent être affichés selon vos besoins.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.camera_alt_rounded,
                          title: '3. Paramètres photo et caméra',
                          items: [
                            'Réglez l’angle de la gimbal, les dimensions du capteur, la résolution et les paramètres de prise de vue.',
                            'Activez les points de caméra pour générer des positions de capture spécifiques lors du survol.',
                            'Les réglages sont utiles pour optimiser la couverture de la zone de mission en fonction du matériel utilisé.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.upload_file_rounded,
                          title: '4. Import / export',
                          items: [
                            'Importez un contour depuis un fichier KML pour le charger sur la carte ou réutiliser un périmètre existant.',
                            'Exportez la zone en KML pour la réutiliser dans d’autres outils ou logiciels.',
                            'Exporte la mission au format DJI Fly ou Litchi selon votre logiciel de vol et votre équipement.',
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildHelpSection(
                          icon: Icons.lightbulb_rounded,
                          title: '5. Fonctionnalités complémentaires',
                          items: [
                            'Passez en mode sombre ou clair selon votre environnement de travail et votre confort visuel.',
                            'Utilisez la recherche de lieux pour centrer rapidement la carte sur un emplacement précis.',
                            'Visualisez la météo et les informations GPS depuis la barre supérieure de l’application.',
                            'Téléchargez les fichiers de mission directement depuis le navigateur ou votre système local selon la plateforme.',
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