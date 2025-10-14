// navigation_map_service.dart
import 'package:geolocator/geolocator.dart';

class NavigationMapService {
  // Calculate distance in kilometers using Haversine formula
  static double calculateDistance(double startLat, double startLng,
      double endLat, double endLng) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng) / 1000;
  }

  static int calculateEstimatedTime(double distanceKm, {
    String routeType = 'driving',
    bool considerTraffic = true,
    String areaType = 'mixed'
  }) {
    if (distanceKm <= 0) return 0;

    double averageSpeed;

    // Set base average speed based on area type
    switch (areaType) {
      case 'urban':
        averageSpeed = 25.0;
        break;
      case 'suburban':
        averageSpeed = 40.0;
        break;
      case 'rural':
        averageSpeed = 60.0;
        break;
      case 'mixed':
      default:
        averageSpeed = 35.0;
    }

    // Calculate base time in hours then convert to minutes
    double baseTimeHours = distanceKm / averageSpeed;
    int baseTimeMinutes = (baseTimeHours * 60).round();

    if (considerTraffic && routeType == 'driving') {
      double trafficFactor = _getTrafficFactor();
      baseTimeMinutes = (baseTimeMinutes * trafficFactor).round();
    }

    // Add fixed time for stops, traffic lights
    int additionalTime = _calculateAdditionalTime(distanceKm, areaType);
    baseTimeMinutes += additionalTime;

    // Ensure minimum time for very short distances
    if (baseTimeMinutes < 3) baseTimeMinutes = 3;

    return baseTimeMinutes;
  }

  // Simulate traffic factor
  static double _getTrafficFactor() {
    final hour = DateTime.now().hour;

    // Peak hours have higher traffic
    if ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19)) {
      return 1.4; // 40% longer during rush hour
    } else if (hour >= 22 || hour <= 5) {
      return 0.8; // 20% faster during night
    } else {
      return 1.1; // 10% longer during normal daytime
    }
  }

  // Calculate additional time for stops, traffic lights
  static int _calculateAdditionalTime(double distanceKm, String areaType) {
    int additionalMinutes = 0;

    // Base additional time per trip
    additionalMinutes += 2; // Starting and ending

    // Additional time based on distance and area type
    if (areaType == 'urban') {
      additionalMinutes += (distanceKm * 2).round(); // More stops in urban areas
    } else if (areaType == 'suburban') {
      additionalMinutes += (distanceKm * 1).round(); // Moderate stops
    } else {
      additionalMinutes += (distanceKm * 0.5).round(); // Fewer stops in rural areas
    }

    return additionalMinutes;
  }

  static String generateGoogleMapsUrl(double startLat, double startLng,
  double endLat, double endLng) {
  return 'https://www.google.com/maps/dir/?api=1'
  '&origin=$startLat,$startLng'
  '&destination=$endLat,$endLng'
  '&travelmode=driving';
  }

  static String generateOpenStreetMapUrl(double startLat, double startLng,
  double endLat, double endLng) {
  return 'https://www.openstreetmap.org/directions?'
  'engine=graphhopper_car'
  '&route=$startLat,$startLng;$endLat,$endLng';
  }

  static String estimateAreaType(double lat, double lng) {
  if (_isInUrbanArea(lat, lng)) {
  return 'urban';
  } else if (_isInSuburbanArea(lat, lng)) {
  return 'suburban';
  } else {
  return 'rural';
  }
  }

  static bool _isInUrbanArea(double lat, double lng) {
  return false;
  }

  static bool _isInSuburbanArea(double lat, double lng) {
  return false;
  }
}