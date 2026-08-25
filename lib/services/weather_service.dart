import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double windSpeed; // en km/h
  final double temperature; // en °C
  final bool isSuccess;

  WeatherData({
    required this.windSpeed,
    required this.temperature,
    this.isSuccess = true,
  });

  factory WeatherData.empty() {
    return WeatherData(windSpeed: 0, temperature: 0, isSuccess: false);
  }
}

class WeatherService {
  /// Récupère la position actuelle et consulte l'API Open-Meteo
  static Future<WeatherData> fetchRealtimeWeather() async {
    try {
      // 1. Gestion des permissions GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return WeatherData.empty();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return WeatherData.empty();
      }

      if (permission == LocationPermission.deniedForever) {
        return WeatherData.empty();
      }

      // 2. Obtention de la position actuelle
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      // 3. Appel API Open-Meteo
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?'
        'latitude=${position.latitude}&'
        'longitude=${position.longitude}&'
        'current=temperature_2m,wind_speed_10m&'
        'wind_speed_unit=kmh',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];

        return WeatherData(
          temperature: (current['temperature_2m'] as num).toDouble(),
          windSpeed: (current['wind_speed_10m'] as num).toDouble(),
        );
      }
    } catch (e) {
      // En cas d'erreur réseau ou timeout
      return WeatherData.empty();
    }
    return WeatherData.empty();
  }
}