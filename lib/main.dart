import 'package:dji_mapper/layouts/home.dart';
import 'package:dji_mapper/presets/preset_manager.dart';
import 'package:dji_mapper/shared/map_provider.dart';
import 'package:dji_mapper/shared/theme_manager.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late SharedPreferences prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  prefs = await SharedPreferences.getInstance();
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
