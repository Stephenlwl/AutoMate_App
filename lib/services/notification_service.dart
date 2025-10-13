import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automate_application/model/notification_model.dart';
import '../blocs/notification_bloc.dart';
import '../globals/navigation_service.dart';
import 'notification_listener_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  NotificationListenerService? _listenerService;

    String? _userId;
    String? _userName;
    String? _userEmail;

  // Initialize notifications
  Future<void> initialize(NotificationBloc notificationBloc, {String? userId, String? userName, String? userEmail}) async {
    // Initialize listener service with bloc
    _listenerService = NotificationListenerService(notificationBloc);

    _userId = userId;
    _userName = userName;
    _userEmail = userEmail;

    _listenerService = NotificationListenerService(notificationBloc);

    // Request permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true, // Request provisional permission for iOS
    );

    debugPrint('Notification permission status: ${settings.authorizationStatus}');

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings =
    InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _onNotificationTap(response);
      },
    );

    // Create notification channel for Android
    await _createNotificationChannel();

    // Configure message handling
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onBackgroundMessageOpened);

    // Get device token
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      debugPrint('Device Token: $token');
      await _saveDeviceToken(token);
    }

    // Token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveDeviceToken);
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'automate_channel',
      'AutoMate Notifications',
      description: 'Notifications for service bookings and towing requests',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _saveDeviceToken(String token) async {
    if (_userId != null) {
      // Save token to user's document in Firestore
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .update({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('Device token saved for user: $_userId');
      } catch (e) {
        debugPrint('Error saving device token: $e');
      }
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');
    _showLocalNotification(message);

    // Update local notification state
    final notification = NotificationModel.fromRemoteMessage(message);
  }

  void _onBackgroundMessageOpened(RemoteMessage message) {
    debugPrint('App opened from background: ${message.messageId}');
    _handleNotificationAction(NotificationModel.fromRemoteMessage(message));
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');

    final payload = response.payload;
    if (payload != null) {
      try {
        final payloadMap = json.decode(payload) as Map<String, dynamic>;
        final notification = NotificationModel.fromJson(payloadMap);
        _handleNotificationAction(notification);
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
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

      debugPrint('Local notification shown: ${notification.title}');
    } catch (e) {
      debugPrint('Error showing local notification: $e');
    }
  }

  void _handleNotificationAction(NotificationModel notification) {
    debugPrint('Handling notification action: ${notification.type}');

    // Use navigatorKey to get context
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('No context available for navigation');
      return;
    }

    switch (notification.type) {
      case 'service_booking':
        Navigator.pushNamed(context, '/service-booking-details',
            arguments: {'bookingId': notification.data['bookingId']});
        break;
      case 'towing_request':
        Navigator.pushNamed(context, '/towing-details',
            arguments: {'requestId': notification.data['requestId']});
        break;
      case 'service_reminder':
        if (_userId != null && _userName != null && _userEmail != null) {
          Navigator.pushNamed(
            context,
            'search-service-center',
            arguments: {
              'userId': _userId,
              'userName': _userName,
              'userEmail': _userEmail,
            },
          );
        } else {
          debugPrint('User data not available for navigation');
          Navigator.pushNamed(context, '/notifications');
        }
        break;
      default:
      // Navigate to notifications page for general notifications
        Navigator.pushNamed(context, '/notifications');
        break;
    }
  }

  // Start listening to real-time updates for a specific user
  void startListeningToUserUpdates(String userId) {
    _listenerService?.startListening(userId);
  }

  // Stop listening
  void stopListening() {
    _listenerService?.stopListening();
  }

  // Subscribe to topics
  Future<void> subscribeToUserTopics(String userId) async {
    await _firebaseMessaging.subscribeToTopic('user_$userId');
    await _firebaseMessaging.subscribeToTopic('service_bookings');
    await _firebaseMessaging.subscribeToTopic('towing_requests');
    debugPrint('Subscribed to topics for user: $userId');
  }

  // Unsubscribe from topics
  Future<void> unsubscribeFromTopics(String userId) async {
    await _firebaseMessaging.unsubscribeFromTopic('user_$userId');
    await _firebaseMessaging.unsubscribeFromTopic('service_bookings');
    await _firebaseMessaging.unsubscribeFromTopic('towing_requests');
  }
}