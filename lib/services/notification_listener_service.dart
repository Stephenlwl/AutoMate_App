import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../blocs/notification_bloc.dart';
import '../model/notification_model.dart';

class NotificationListenerService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationBloc _notificationBloc;

  List<StreamSubscription<dynamic>> _subscriptions = [];

  final Map<String, DateTime> _processedNotifications = {};
  static const Duration _deduplicationWindow = Duration(minutes: 2);

  NotificationListenerService(this._notificationBloc);

  void startListening(String userId) {
    _listenToServiceBookings(userId);
    _listenToTowingRequests(userId);
    _checkServiceMaintenanceReminders(userId);
  }

  void stopListening() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _processedNotifications.clear();
  }

  void _listenToServiceBookings(String userId) {
    final subscription = _firestore
        .collection('service_bookings')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      for (var change in snapshot.docChanges) {
        // Only process modifications and additions
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;

          // Skip if this is a local write
          if (change.doc.metadata.hasPendingWrites) {
            continue;
          }

          final bookingId = change.doc.id;
          final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification(bookingId, updatedAt)) {
            _handleServiceBookingUpdate(bookingId, data);
          }
        }
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final bookingId = change.doc.id;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification(bookingId, createdAt)) {
            _handleNewServiceBooking(bookingId, data);
          }
        }
      }
    });

    _subscriptions.add(subscription);
  }

  void _listenToTowingRequests(String userId) {
    final subscription = _firestore
        .collection('towing_requests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data() as Map<String, dynamic>;
          final requestId = change.doc.id;
          final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification(requestId, updatedAt)) {
            _handleTowingRequestUpdate(requestId, data);
          }
        }

        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final requestId = change.doc.id;
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification(requestId, createdAt)) {
            _handleNewTowingRequest(requestId, data);
          }
        }
      }
    });

    _subscriptions.add(subscription);
  }

  bool _shouldProcessNotification(String docId, DateTime timestamp) {
    final now = DateTime.now();
    final key = '$docId-${timestamp.millisecondsSinceEpoch}';

    // Clean old entries first
    _processedNotifications.removeWhere((key, processedTime) {
      return now.difference(processedTime) > _deduplicationWindow;
    });

    // Check if we recently processed this
    if (_processedNotifications.containsKey(key)) {
      return false;
    }

    // Mark as processed
    _processedNotifications[key] = now;
    return true;
  }

  void _checkServiceMaintenanceReminders(String userId) {
    final subscription = _firestore
        .collection('car_owners')
        .doc(userId)
        .snapshots()
        .listen((doc) async {
      if (doc.exists) {
        final data = doc.data()!;
        final vehicles = data['vehicles'] as List? ?? [];

        for (var vehicle in vehicles) {
          final serviceMaintenances = vehicle['serviceMaintenances'] as List? ?? [];
          await _checkVehicleServiceReminders(serviceMaintenances, vehicle);
        }
      }
    });

    _subscriptions.add(subscription);
  }

  Future<void> _checkVehicleServiceReminders(
      List<dynamic> serviceMaintenances,
      Map<String, dynamic> vehicle
      ) async {
    final currentMileage = vehicle['lastServiceMileage'] as int? ?? 0;
    final vehicleInfo = '${vehicle['make']} ${vehicle['model']} ${vehicle['plateNumber']}';

    for (var maintenance in serviceMaintenances) {
      final maintenanceMap = maintenance as Map<String, dynamic>;
      await _checkSingleServiceReminder(maintenanceMap, currentMileage, vehicleInfo);
    }
  }

  Future<void> _checkSingleServiceReminder(
      Map<String, dynamic> maintenance,
      int currentMileage,
      String vehicleInfo
      ) async {
    final serviceType = maintenance['serviceType'] as String? ?? 'Service';
    final nextServiceMileage = maintenance['nextServiceMileage'] as int?;
    final nextServiceDate = maintenance['nextServiceDate'] as String?;

    // Check mileage-based reminder
    if (nextServiceMileage != null && currentMileage > 0) {
      final mileageDifference = nextServiceMileage - currentMileage;
      if (mileageDifference <= 500 && mileageDifference > 0) {
        await _showServiceReminderNotification(
          title: 'Service Mileage Approaching',
          body: 'Your $serviceType for $vehicleInfo is due in $mileageDifference km',
          type: 'service_reminder',
          data: {
            'serviceType': serviceType,
            'vehicleInfo': vehicleInfo,
            'currentMileage': currentMileage,
            'dueMileage': nextServiceMileage,
            'reminderType': 'mileage',
          },
        );
      }
    }

    if (nextServiceDate != null) {
      try {
        final dueDate = DateTime.parse(nextServiceDate);
        final now = DateTime.now();
        final daysUntilDue = dueDate.difference(now).inDays;

        if (daysUntilDue <= 7 && daysUntilDue >= 0) {
          await _showServiceReminderNotification(
            title: 'Service Date Approaching',
            body: 'Your $serviceType for $vehicleInfo is due in $daysUntilDue days',
            type: 'service_reminder',
            data: {
              'serviceType': serviceType,
              'vehicleInfo': vehicleInfo,
              'dueDate': nextServiceDate,
              'daysUntilDue': daysUntilDue,
              'reminderType': 'date',
            },
          );
        }

        // Overdue notification
        if (daysUntilDue < 0) {
          await _showServiceReminderNotification(
            title: 'Service Overdue',
            body: 'Your $serviceType for $vehicleInfo is ${daysUntilDue.abs()} days overdue',
            type: 'service_reminder',
            data: {
              'serviceType': serviceType,
              'vehicleInfo': vehicleInfo,
              'dueDate': nextServiceDate,
              'daysOverdue': daysUntilDue.abs(),
              'reminderType': 'overdue',
            },
          );
        }
      } catch (e) {
        debugPrint('Error parsing service date: $e');
      }
    }
  }

  void _handleServiceBookingUpdate(String bookingId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'unknown';
    final serviceCenterId = data['serviceCenterId'] ?? '';

    // Get service center name for better notification
    _getServiceCenterName(serviceCenterId).then((serviceCenterName) {
      final notification = NotificationModel(
        id: 'service_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Service Booking Updated',
        body: 'Your service at $serviceCenterName is now ${_formatStatus(status)}',
        type: 'service_booking',
        data: {
          'bookingId': bookingId,
          'status': status,
          'serviceCenterId': serviceCenterId,
        },
        timestamp: DateTime.now(),
      );

      // Add to Bloc state
      _notificationBloc.add(NewNotificationEvent(notification));

      // Show local notification
      _showLocalNotification(notification);
    });
  }

  void _handleNewServiceBooking(String bookingId, Map<String, dynamic> data) {
    final serviceCenterId = data['serviceCenterId'] ?? '';

    _getServiceCenterName(serviceCenterId).then((serviceCenterName) {
      final notification = NotificationModel(
        id: 'service_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Service Booking Created',
        body: 'Your service booking at $serviceCenterName has been confirmed',
        type: 'service_booking',
        data: {
          'bookingId': bookingId,
          'status': data['status'] ?? 'pending',
          'serviceCenterId': serviceCenterId,
        },
        timestamp: DateTime.now(),
      );

      _notificationBloc.add(NewNotificationEvent(notification));
      _showLocalNotification(notification);
    });
  }

  void _handleTowingRequestUpdate(String requestId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'unknown';

    final notification = NotificationModel(
      id: 'towing_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Towing Request Updated',
      body: 'Your towing request is now ${_formatStatus(status)}',
      type: 'towing_request',
      data: {
        'requestId': requestId,
        'status': status,
      },
      timestamp: DateTime.now(),
    );

    _notificationBloc.add(NewNotificationEvent(notification));
    _showLocalNotification(notification);
  }

  void _handleNewTowingRequest(String requestId, Map<String, dynamic> data) {
    final notification = NotificationModel(
      id: 'towing_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Towing Request Created',
      body: 'Your towing request has been submitted',
      type: 'towing_request',
      data: {
        'requestId': requestId,
        'status': data['status'] ?? 'pending',
      },
      timestamp: DateTime.now(),
    );

    _notificationBloc.add(NewNotificationEvent(notification));
    _showLocalNotification(notification);
  }

  Future<void> _showServiceReminderNotification({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final notification = NotificationModel(
      id: 'service_reminder_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    // Add to Bloc state
    _notificationBloc.add(NewNotificationEvent(notification));

    // Show local notification
    await _showLocalNotification(notification);
  }

  Future<String> _getServiceCenterName(String serviceCenterId) async {
    if (serviceCenterId.isEmpty) return 'Service Center';

    try {
      final doc = await _firestore
          .collection('service_centers')
          .doc(serviceCenterId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final serviceCenterInfo = data['serviceCenterInfo'] as Map<String, dynamic>?;
        return serviceCenterInfo?['name'] ?? 'Service Center';
      }
    } catch (e) {
      debugPrint('Error getting service center name: $e');
    }

    return 'Service Center';
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'confirmed': return 'Confirmed';
      case 'assigned': return 'Assigned';
      case 'in_progress': return 'In Progress';
      case 'ready_to_collect': return 'Ready to Collect';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return status;
    }
  }

  Future<void> _showLocalNotification(NotificationModel notification) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'automate_channel',
        'AutoMate Notifications',
        channelDescription: 'Notifications for service bookings and towing requests',
        importance: Importance.high,
        priority: Priority.high,
        colorized: true,
        color: Color(0xFFFF6B00),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await FlutterLocalNotificationsPlugin().show(
        notification.id.hashCode,
        notification.title,
        notification.body,
        details,
        payload: json.encode(notification.toJson()),
      );

      debugPrint('Local notification shown: ${notification.title}');
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }
}