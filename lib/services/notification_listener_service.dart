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
  final String _userId;
  bool _isListening = false;
  List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, DateTime> _lastNotificationTime = {};
  static const Duration _deduplicationWindow = Duration(minutes: 2);
  final Map<String, DateTime> _processedNotifications = {};

  NotificationListenerService(this._notificationBloc, this._userId);

  void startListening() {
    if (_isListening) return;
    _isListening = true;

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _handleFirebaseNotification(message);
    });

    _listenToServiceBookings();
    _listenToTowingRequests();
    _checkServiceMaintenanceReminders();
  }

  void _handleFirebaseNotification(RemoteMessage message) {
    final notification = NotificationModel.fromRemoteMessage(
        message,
        currentUserId: _userId
    );

    // Check if recently processed a similar notification
    if (_shouldProcessNotification('fcm_${notification.title}_${notification.body}')) {
      _notificationBloc.add(NewNotificationEvent(
        notification,
        shouldShowPopup: true,
      ));
    }
  }

  bool _shouldProcessNotification(String notificationKey) {
    final now = DateTime.now();
    final lastTime = _lastNotificationTime[notificationKey];

    // Clean old entries
    _lastNotificationTime.removeWhere((key, time) {
      return now.difference(time) > _deduplicationWindow;
    });

    // If recently processed then skip
    if (lastTime != null && now.difference(lastTime) < _deduplicationWindow) {
      return false;
    }

    // Mark as processed
    _lastNotificationTime[notificationKey] = now;
    return true;
  }

  void _listenToServiceBookings() {
    final subscription = _firestore
        .collection('service_bookings')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;

          // Skip if this is a local write
          if (change.doc.metadata.hasPendingWrites) {
            continue;
          }
          final documentUserId = data['userId']?.toString();
          if (documentUserId != _userId) {
            continue;
          }

          final bookingId = change.doc.id;
          final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification('service_$bookingId')) {
            if (change.type == DocumentChangeType.added) {
              _handleNewServiceBooking(bookingId, data);
            } else {
              _handleServiceBookingUpdate(bookingId, data);
            }
          }
        }
      }
    });

    _subscriptions.add(subscription);
  }

  void _listenToTowingRequests() {
    final subscription = _firestore
        .collection('towing_requests')
        .where('userId', isEqualTo: _userId)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified ||
            change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;

          final documentUserId = data['userId']?.toString();
          if (documentUserId != _userId) {
            debugPrint('Skipping towing request for different user: $documentUserId');
            continue;
          }

          final requestId = change.doc.id;
          final timestamp = (data['updatedAt'] as Timestamp?)?.toDate() ??
              (data['createdAt'] as Timestamp?)?.toDate() ??
              DateTime.now();

          if (_shouldProcessNotification('towing_$requestId')) {
            if (change.type == DocumentChangeType.added) {
              _handleNewTowingRequest(requestId, data);
            } else {
              _handleTowingRequestUpdate(requestId, data);
            }
          }
        }
      }
    });

    _subscriptions.add(subscription);
  }

  void _handleServiceBookingUpdate(String bookingId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final serviceCenterId = data['serviceCenterId'] ?? '';
    final vehicleMake = data['vehicle']['make'] ?? 'Your vehicle';
    final vehicleModel = data['vehicle']['model'] ?? '';
    final vehicleYear = data['vehicle']['year'] ?? '';
    final plateNumber = data['vehicle']['plateNumber'] ?? '';
    final serviceType = data['serviceType'] ?? 'service';
    final vehicleInfo = '${vehicleMake ?? ''} ${vehicleModel ?? ''}${vehicleYear != null ? ' ($vehicleYear)' : ''} - ${plateNumber ?? 'No Plate'}'.trim();
    _getServiceCenterName(serviceCenterId).then((serviceCenterName) {
      final notification = NotificationModel(
        id: 'service_${_userId}_${bookingId}_${DateTime.now().millisecondsSinceEpoch}',
        title: _getServiceBookingTitle(status),
        userId: _userId,
        body: _getServiceBookingBody(status, serviceCenterName, vehicleInfo, serviceType, data),
        type: 'service_booking',
        data: {
          'bookingId': bookingId,
          'userId': _userId,
          'status': status,
          'serviceCenterId': serviceCenterId,
          'vehicleInfo': vehicleInfo
        },
        timestamp: DateTime.now(),
      );

      _notificationBloc.add(NewNotificationEvent(
        notification,
        shouldShowPopup: true,
      ));
    });
  }

  void _handleNewServiceBooking(String bookingId, Map<String, dynamic> data) {
    final serviceCenterId = data['serviceCenterId'] ?? '';
    final vehicleMake = data['vehicle']['make'] ?? 'Your vehicle';
    final vehicleModel = data['vehicle']['model'] ?? '';
    final vehicleYear = data['vehicle']['year'] ?? '';
    final plateNumber = data['vehicle']['plateNumber'] ?? '';
    final vehicleInfo = '${vehicleMake ?? ''} ${vehicleModel ?? ''}${vehicleYear != null ? ' ($vehicleYear)' : ''} - ${plateNumber ?? 'No Plate'}'.trim();
    final serviceType = data['serviceType'] ?? 'service';
    final status = data['status'] ?? 'pending';

    _getServiceCenterName(serviceCenterId).then((serviceCenterName) {
      final notification = NotificationModel(
        id: 'service_${bookingId}_${DateTime.now().millisecondsSinceEpoch}',
        userId: _userId,
        title: _getServiceBookingTitle(status),
        body: _getServiceBookingBody(status, serviceCenterName, vehicleInfo, serviceType, data),
        type: 'service_booking',
        data: {
          'bookingId': bookingId,
          'status': data['status'] ?? 'pending',
          'serviceCenterId': serviceCenterId,
          'vehicleInfo': vehicleInfo,
        },
        timestamp: DateTime.now(),
      );

      _notificationBloc.add(NewNotificationEvent(
        notification,
        shouldShowPopup: true,
      ));
    });
  }

  void _handleTowingRequestUpdate(String requestId, Map<String, dynamic> data) {
    final status = data['status'] ?? 'unknown';
    final vehicleMake = data['vehicleInfo']['make'] ?? 'Your vehicle';
    final vehicleModel = data['vehicleInfo']['model'] ?? '';
    final vehicleYear = data['vehicleInfo']['year'] ?? '';
    final plateNumber = data['vehicleInfo']['plateNumber'] ?? '';
    final vehicleInfo = '${vehicleMake ?? ''} ${vehicleModel ?? ''}${vehicleYear != null ? ' ($vehicleYear)' : ''} - ${plateNumber ?? 'No Plate'}'.trim();
    final location = data['location']?['customer']?['address']?['full'] ?? 'your location';

    final notification = NotificationModel(
      id: 'towing_${requestId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: _userId,
      title: _getTowingRequestTitle(status),
      body: _getTowingRequestBody(status, vehicleInfo, location, data),
      type: 'towing_request',
      data: {
        'requestId': requestId,
        'status': status,
        'vehicleInfo': vehicleInfo,
        'location': location,
      },
      timestamp: DateTime.now(),
    );

    _notificationBloc.add(NewNotificationEvent(
      notification,
      shouldShowPopup: true,
    ));
  }

  void _handleNewTowingRequest(String requestId, Map<String, dynamic> data) {
    final vehicleMake = data['vehicleInfo']['make'] ?? 'Your vehicle';
    final vehicleModel = data['vehicleInfo']['model'] ?? '';
    final vehicleYear = data['vehicleInfo']['year'] ?? '';
    final plateNumber = data['vehicleInfo']['plateNumber'] ?? '';
    final vehicleInfo = '${vehicleMake ?? ''} ${vehicleModel ?? ''}${vehicleYear != null ? ' ($vehicleYear)' : ''} - ${plateNumber ?? 'No Plate'}'.trim();
    final location = data['location']?['customer']?['address']?['full'] ?? 'your location';
    final status = data['status'] ?? 'pending';

    final notification = NotificationModel(
      id: 'towing_${requestId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: _userId,
      title: _getTowingRequestTitle(status),
      body: _getTowingRequestBody(status, vehicleInfo, location, data),
      type: 'towing_request',
      data: {
        'requestId': requestId,
        'status': data['status'] ?? 'pending',
        'vehicleInfo': vehicleInfo,
        'location': location,
      },
      timestamp: DateTime.now(),
    );

    _notificationBloc.add(NewNotificationEvent(
      notification,
      shouldShowPopup: true,
    ));
  }

  String _getServiceBookingTitle(String status) {
    switch (status) {
      case 'pending':
        return 'Booking Received';
      case 'confirmed':
        return 'Booking Confirmed';
      case 'assigned':
        return 'Technician Assigned';
      case 'in_progress':
        return 'Service In Progress';
      case 'ready_to_collect':
        return 'Vehicle Ready for Pickup';
      case 'invoice_generated':
        return 'Invoice has generated';
      case 'completed':
        return 'Service Completed';
      case 'cancelled':
        return 'Booking Cancelled';
      case 'declined':
        return 'Booking Declined';
      default:
        return 'Service Booking Updated';
    }
  }

  String _getServiceBookingBody(String status, String serviceCenterName, String vehicleInfo, String serviceType, Map<String, dynamic> data) {
    switch (status) {
      case 'pending':
        return 'Your service for $vehicleInfo at $serviceCenterName is being processed. We\'ll notify you once confirmed.';
      case 'confirmed':
        final scheduledDate = data['scheduledDate'] ?? '';
        if (scheduledDate != '') {
          return 'Your service for $vehicleInfo at $serviceCenterName is confirmed for $scheduledDate. Please arrive on time.';
        }
        return 'Your service for $vehicleInfo at $serviceCenterName has been confirmed!';
      case 'assigned':
        final technician = data['technicianName'] ?? 'a technician';
        return '$technician has been assigned to your service for $vehicleInfo.';
      case 'in_progress':
        return 'Your service for $vehicleInfo is now being worked on. We\'ll update you when complete.';
      case 'ready_to_collect':
        return 'Great news! Your $vehicleInfo is ready for pickup at $serviceCenterName.';
      case 'invoice_generated':
        return 'Invoice has generated, please review then proceed to payment';
      case 'completed':
        return 'Thank you for choosing $serviceCenterName! Your service for $vehicleInfo has been completed successfully.';
      case 'cancelled':
        return 'Your booking at $serviceCenterName has been cancelled.';
      case 'declined':
        return 'Your booking at $serviceCenterName has been declined.';
      default:
        return 'Your service booking status has been updated to ${_formatStatus(status)}.';
    }
  }

  String _getTowingRequestTitle(String status) {
    switch (status) {
      case 'pending':
        return 'Towing Request Received';
      case 'accepted':
        return 'Towing Request Accepted';
      case 'dispatched':
        return 'Dispatching';
      case 'in_progress':
        return 'Towing Service is in progress';
      case 'invoice_generated':
        return 'Invoice has generated';
      case 'completed':
        return 'Towing Completed';
      case 'cancelled':
        return 'Towing Cancelled';
      case 'declined':
        return 'Towing Request Declined';
      default:
        return 'Towing Request Updated';
    }
  }

  String _getTowingRequestBody(String status, String vehicleInfo, String location, Map<String, dynamic> data) {
    switch (status) {
      case 'pending':
        return 'We\'re assigning available towing driver near $location for your $vehicleInfo.';
      case 'assigned':
        final driverName = data['driverName'] ?? 'a driver';
        final eta = data['estimatedDuration'] ?? 'shortly';
        return '$driverName has been assigned to your request. Estimated arrival: $eta.';
      case 'dispatched':
        final driverName = data['driverName'] ?? 'Our driver';
        return '$driverName is on the way to $location';
      case 'in_progress':
        return 'Driver Arrived at your location, and service started!';
      case 'completed':
        return 'Full payment has received, Towing Service has marked as completed!';
      case 'cancelled':
        return 'Your towing request was cancelled';
      case 'invoice_generated':
        return 'Invoice has generated, please review then proceed to payment';
      default:
        return 'Your towing request status has been updated.';
    }
  }

  Future<void> _showServiceReminderNotification({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final notification = NotificationModel(
      id: 'service_reminder_${DateTime.now().millisecondsSinceEpoch}',
      userId: _userId,
      title: title,
      body: body,
      type: type,
      data: data,
      timestamp: DateTime.now(),
    );

    _notificationBloc.add(NewNotificationEvent(
      notification,
      shouldShowPopup: true,
    ));
  }

  void stopListening() {
    if (!_isListening) return;

    _isListening = false;

    // Cancel all subscriptions
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Clear processed notifications
    _processedNotifications.clear();
    _lastNotificationTime.clear();

    debugPrint('NotificationListenerService stopped listening');
  }

  void _checkServiceMaintenanceReminders() {
    final subscription = _firestore
        .collection('car_owners')
        .doc(_userId)
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
          title: 'Service Due Soon - $vehicleInfo',
          body: 'Your ${_getServiceTypeDisplayName(serviceType)} is due in $mileageDifference km. Book your service now!',
          type: 'service_reminder',
          data: {
            'serviceType': serviceType,
            'vehicleInfo': vehicleInfo,
            'currentMileage': currentMileage,
            'dueMileage': nextServiceMileage,
            'reminderType': 'mileage',
          },
        );
      } else if (mileageDifference <= 0) {
        await _showServiceReminderNotification(
          title: 'Service Overdue - $vehicleInfo',
          body: 'Your ${_getServiceTypeDisplayName(serviceType)} is ${mileageDifference.abs()} km overdue. Please schedule service immediately.',
          type: 'service_reminder',
          data: {
            'serviceType': serviceType,
            'vehicleInfo': vehicleInfo,
            'currentMileage': currentMileage,
            'dueMileage': nextServiceMileage,
            'reminderType': 'overdue_mileage',
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
            title: 'Service Appointment - $vehicleInfo',
            body: 'Your ${_getServiceTypeDisplayName(serviceType)} is due in $daysUntilDue days. Get ready for your appointment!',
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

        if (daysUntilDue < 0) {
          await _showServiceReminderNotification(
            title: 'Service Overdue - $vehicleInfo',
            body: 'Your ${_getServiceTypeDisplayName(serviceType)} is ${daysUntilDue.abs()} days overdue. Please contact your service center.',
            type: 'service_reminder',
            data: {
              'serviceType': serviceType,
              'vehicleInfo': vehicleInfo,
              'dueDate': nextServiceDate,
              'daysOverdue': daysUntilDue.abs(),
              'reminderType': 'overdue_date',
            },
          );
        }
      } catch (e) {
        debugPrint('Error parsing service date: $e');
      }
    }
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

  String _getServiceTypeDisplayName(String serviceType) {
    final displayNames = {
      'engine_oil': 'Engine Oil Change',
      'alignment': 'Wheel Alignment',
      'battery': 'Battery Replacement',
      'tire_rotation': 'Tire Rotation',
      'brake_fluid': 'Brake Fluid Change',
      'air_filter': 'Air Filter Replacement',
      'coolant': 'Coolant Flush',
      'gear_oil': 'Gear Oil',
      'at_fluid': 'AT Fluid',
    };
    return displayNames[serviceType] ?? serviceType.replaceAll('_', ' ').toUpperCase();
  }
}