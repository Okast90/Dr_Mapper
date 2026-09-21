import 'package:dji_mapper/layouts/home.dart';
import 'package:dji_mapper/presets/preset_manager.dart';
import 'package:dji_mapper/shared/map_provider.dart';
import 'package:dji_mapper/shared/theme_manager.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late final PreferencesStore prefs;

class PreferencesStore {
  final SharedPreferences? _preferences;
  final Map<String, Object> _fallbackValues = <String, Object>{};

  PreferencesStore(this._preferences);

  bool? getBool(String key) => _preferences?.getBool(key) ?? _fallbackValues[key] as bool?;
  int? getInt(String key) => _preferences?.getInt(key) ?? _fallbackValues[key] as int?;
  String? getString(String key) => _preferences?.getString(key) ?? _fallbackValues[key] as String?;

  Future<bool> setBool(String key, bool value) async {
    if (_preferences != null) return _preferences.setBool(key, value);
    _fallbackValues[key] = value;
    return true;
  }

  Future<bool> setInt(String key, int value) async {
    if (_preferences != null) return _preferences.setInt(key, value);
    _fallbackValues[key] = value;
    return true;
  }

  Future<bool> setString(String key, String value) async {
    if (_preferences != null) return _preferences.setString(key, value);
    _fallbackValues[key] = value;
    return true;
  }

  Future<bool> remove(String key) async {
    if (_preferences != null) return _preferences.remove(key);
    _fallbackValues.remove(key);
    return true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    prefs = PreferencesStore(await SharedPreferences.getInstance());
  } catch (_) {
    prefs = PreferencesStore(null);
  }
  PresetManager.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ValueListenables()),
        ChangeNotifierProvider(create: (context) => ThemeManager()),
        ChangeNotifierProvider(create: (context) => MapProvider()),
      ],
      child: DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
        return Consumer<ThemeManager>(builder: (context, theme, child) {
          return MaterialApp(
            title: 'DJI Mapper',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: lightColorScheme ??
                  ColorScheme.fromSeed(seedColor: Colors.blue),
              useMaterial3: true,
              scaffoldBackgroundColor: const Color(0xFFF4F7FF),
              appBarTheme: const AppBarTheme(
                elevation: 0,
                centerTitle: false,
                surfaceTintColor: Colors.transparent,
              ),
              cardTheme: CardThemeData(
                elevation: 3,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
              tabBarTheme: const TabBarThemeData(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: Colors.white, width: 3),
                ),
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: (darkColorScheme ??
                      ColorScheme.fromSeed(
                          seedColor: Colors.blue, brightness: Brightness.dark))
                  .copyWith(
                    surface: Colors.black,
                    onSurface: Colors.white,
                    background: Colors.black,
                    onBackground: Colors.white,
                    surfaceContainerHighest: const Color(0xFF111111),
                  ),
              useMaterial3: true,
              scaffoldBackgroundColor: Colors.black,
              dialogBackgroundColor: Colors.black,
              canvasColor: Colors.black,
              cardColor: Colors.black,
              appBarTheme: const AppBarTheme(
                elevation: 0,
                centerTitle: false,
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              cardTheme: CardThemeData(
                color: Colors.black,
                elevation: 3,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
              ),
              tabBarTheme: const TabBarThemeData(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: Colors.white, width: 3),
                ),
              ),
            ),
            themeMode: theme.themeMode,
            home: const HomeLayout(),
          );
        });
      }),
    );
  }
}
