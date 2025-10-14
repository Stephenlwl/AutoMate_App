import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'navigation_map_service.dart';

class LocationService {
  static StreamSubscription<Position>? _positionStream;
  static bool _isTracking = false;

  static Future<void> startAutomaticLocationUpdates(
      String requestId,
      Map<String, dynamic> driverData
      ) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions permanently denied');
      }

      await stopLocationUpdates();

      final locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 50, // Update every 50 meters
      );

      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) async {
        await _updateDriverLocation(requestId, position, driverData);
      });

      _isTracking = true;

      // Get initial position immediately
      final initialPosition = await Geolocator.getCurrentPosition();
      await _updateDriverLocation(requestId, initialPosition, driverData);

    } catch (e) {
      debugPrint('Error starting location updates: $e');
      rethrow;
    }
  }

  static Future<void> stopLocationUpdates() async {
    await _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
  }

  static Future<void> _updateDriverLocation(
      String requestId,
      Position position,
      Map<String, dynamic> driverData
      ) async {
    try {
      final driverLocation = {
        'towingDriver': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': Timestamp.now(),
          'contactNumber': driverData['phoneNo'],
          'driverName': driverData['name'],
        }
      };

      await FirebaseFirestore.instance
          .collection('towing_requests')
          .doc(requestId)
          .update({
        'location.towingDriver': driverLocation['towingDriver'],
        'updatedAt': Timestamp.now(),
      });

      await _calculateAndUpdateDuration(requestId, position);

    } catch (e) {
      debugPrint('Error updating driver location: $e');
    }
  }

  static Future<void> _calculateAndUpdateDuration(
      String requestId,
      Position driverPosition
      ) async {
    try {
      final requestDoc = await FirebaseFirestore.instance
          .collection('towing_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) return;

      final request = requestDoc.data()!;
      final customerLocation = request['location']?['customer'];

      if (customerLocation == null) return;

      final double? customerLat = customerLocation['latitude']?.toDouble();
      final double? customerLng = customerLocation['longitude']?.toDouble();

      if (customerLat == null || customerLng == null) return;

      // Calculate distance using NavigationMapService
      final distanceInKm = NavigationMapService.calculateDistance(
        driverPosition.latitude,
        driverPosition.longitude,
        customerLat,
        customerLng,
      );

      // Calculate estimated duration using the sophisticated NavigationMapService
      final estimatedDurationMinutes = NavigationMapService.calculateEstimatedTime(
        distanceInKm,
        areaType: NavigationMapService.estimateAreaType(customerLat, customerLng),
        considerTraffic: true,
      );

      await FirebaseFirestore.instance
          .collection('towing_requests')
          .doc(requestId)
          .update({
        'liveDistance': distanceInKm,
        'estimatedDuration': estimatedDurationMinutes,
        'lastLocationUpdate': Timestamp.now(),
      });

    } catch (e) {
      debugPrint('Error calculating duration: $e');
    }
  }

  static bool get isTracking => _isTracking;
}