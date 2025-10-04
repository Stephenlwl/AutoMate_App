import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automate_application/model/notification_model.dart';
import '../blocs/notification_bloc.dart';
import '../globals/navigation_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Initialize notifications
  Future<void> initialize() async {
    // Request permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Notification permissions granted');
    }

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings();
    const InitializationSettings initializationSettings =
    InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        _onNotificationTap(response);
      },
    );

    // Configure message handling
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onBackgroundMessageOpened);

    // Get device token
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _saveDeviceToken(token);
    }

    // Token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveDeviceToken);
  }

  Future<void> _saveDeviceToken(String token) async {
    // Save token to user's document in Firestore
    // You'll need to get the current user ID
    debugPrint('Device Token: $token');
  }

  void _onForegroundMessage(RemoteMessage message) {
    _showLocalNotification(message);
    // Update local notification state
    NotificationBloc().add(NewNotificationEvent(
        NotificationModel.fromRemoteMessage(message)
    ));
  }

  void _onBackgroundMessageOpened(RemoteMessage message) {
    // Handle when app is opened from terminated state
    _handleNotificationAction(NotificationModel.fromRemoteMessage(message));
  }

  void _onNotificationTap(NotificationResponse response) {
    // Handle local notification tap
    final payload = response.payload;
    if (payload != null) {
      try {
        // Parse the JSON string back to a Map
        final payloadMap = json.decode(payload) as Map<String, dynamic>;
        final notification = NotificationModel.fromJson(payloadMap);
        _handleNotificationAction(notification);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = NotificationModel.fromRemoteMessage(message);

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

    await _localNotifications.show(
      notification.id.hashCode,
      notification.title,
      notification.body,
      details,
      payload: json.encode(notification.toJson()),
    );
  }

  void _handleNotificationAction(NotificationModel notification) {
    // Navigate based on notification type
    final context = navigatorKey.currentContext;
    if (context == null) return;

    switch (notification.type) {
      case 'service_booking':
        Navigator.pushNamed(context, '/service-booking-details',
            arguments: {'bookingId': notification.data['bookingId']});
        break;
      case 'towing_request':
        Navigator.pushNamed(context, '/towing-details',
            arguments: {'requestId': notification.data['requestId']});
        break;
      case 'payment':
        Navigator.pushNamed(context, '/payment-details',
            arguments: {'paymentId': notification.data['paymentId']});
        break;
    }
  }

  // Subscribe to topics
  Future<void> subscribeToUserTopics(String userId) async {
    await _firebaseMessaging.subscribeToTopic('user_$userId');
    await _firebaseMessaging.subscribeToTopic('service_bookings');
    await _firebaseMessaging.subscribeToTopic('towing_requests');
  }

  // Unsubscribe from topics
  Future<void> unsubscribeFromTopics(String userId) async {
    await _firebaseMessaging.unsubscribeFromTopic('user_$userId');
    await _firebaseMessaging.unsubscribeFromTopic('service_bookings');
    await _firebaseMessaging.unsubscribeFromTopic('towing_requests');
  }
}