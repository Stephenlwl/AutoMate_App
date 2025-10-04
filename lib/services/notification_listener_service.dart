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

  // Use dynamic type or specific QuerySnapshot type
  List<StreamSubscription<dynamic>> _subscriptions = [];

  void startListening(String userId) {
    _listenToServiceBookings(userId);
    _listenToTowingRequests(userId);
  }

  void stopListening() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _listenToServiceBookings(String userId) {
    final subscription = _firestore
        .collection('service_bookings')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((QuerySnapshot snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final beforeData = change.doc.data()! as Map<String, dynamic>;
          final afterData = change.doc.data()! as Map<String, dynamic>;

          // Check if status changed
          if (beforeData['status'] != afterData['status']) {
            _showLocalNotification(
              title: 'Service Booking Update',
              body: 'Your service booking is now ${afterData['status']}',
              type: 'service_booking',
              data: {
                'bookingId': change.doc.id,
                'status': afterData['status'],
              },
            );
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
          final beforeData = change.doc.data()! as Map<String, dynamic>;
          final afterData = change.doc.data()! as Map<String, dynamic>;

          if (beforeData['status'] != afterData['status']) {
            _showLocalNotification(
              title: 'Towing Request Update',
              body: 'Your towing request is now ${afterData['status']}',
              type: 'towing_request',
              data: {
                'requestId': change.doc.id,
                'status': afterData['status'],
              },
            );
          }
        }

        // Also listen for new towing requests
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()! as Map<String, dynamic>;
          _showLocalNotification(
            title: 'Towing Request Created',
            body: 'Your towing request has been created',
            type: 'towing_request',
            data: {
              'requestId': change.doc.id,
              'status': data['status'] ?? 'pending',
            },
          );
        }
      }
    });

    _subscriptions.add(subscription);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    try {
      final notification = NotificationModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        type: type,
        data: data,
        timestamp: DateTime.now(),
      );

      // Show local notification
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

      debugPrint('Local notification shown: $title');
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }
}