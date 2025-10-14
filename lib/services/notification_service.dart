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

  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserEmail;
  NotificationBloc? _notificationBloc;

  // Initialize notifications with user data
  Future<void> initialize(
      NotificationBloc notificationBloc, {
        required String userId,
        String? userName,
        String? userEmail,
      }) async {
    _notificationBloc = notificationBloc;
    _currentUserId = userId;
    _currentUserName = userName;
    _currentUserEmail = userEmail;

    // Initialize listener service with current user ID
    _listenerService = NotificationListenerService(notificationBloc, userId);

    // Request permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
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

    // Start listening and subscribe to topics
    _listenerService?.startListening();
    await subscribeToUserTopics(userId);
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
    if (_currentUserId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('car_owners')
            .doc(_currentUserId)
            .update({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('Device token saved for user: $_currentUserId');
      } catch (e) {
        debugPrint('Error saving device token: $e');
      }
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.messageId}');

    // Create notification with current user context
    final notification = NotificationModel.fromRemoteMessage(
      message,
      currentUserId: _currentUserId ?? '',
    );

    // Only show and process if it belongs to current user
    if (notification.userId == _currentUserId) {
      _showLocalNotification(notification);
    }
  }

  void _onBackgroundMessageOpened(RemoteMessage message) {
    debugPrint('App opened from background: ${message.messageId}');

    final notification = NotificationModel.fromRemoteMessage(
      message,
      currentUserId: _currentUserId ?? '',
    );

    if (notification.userId == _currentUserId) {
      _handleNotificationAction(notification);
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');

    final payload = response.payload;
    if (payload != null) {
      try {
        final payloadMap = json.decode(payload) as Map<String, dynamic>;
        final notification = NotificationModel.fromJson(payloadMap);

        // Only handle if it belongs to current user
        if (notification.userId == _currentUserId) {
          _handleNotificationAction(notification);
        }
      } catch (e) {
        debugPrint('Error parsing notification payload: $e');
      }
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
        if (_currentUserId != null && _currentUserName != null && _currentUserEmail != null) {
          Navigator.pushNamed(
            context,
            'search-service-center',
            arguments: {
              'userId': _currentUserId,
              'userName': _currentUserName,
              'userEmail': _currentUserEmail,
            },
          );
        } else {
          debugPrint('User data not available for navigation');
          Navigator.pushNamed(context, '/notifications');
        }
        break;
      default:
        Navigator.pushNamed(context, '/notifications');
        break;
    }
  }

  // Update user data when user changes
  void updateUserData({required String userId, String? userName, String? userEmail}) {
    _currentUserId = userId;
    _currentUserName = userName;
    _currentUserEmail = userEmail;

    // Reinitialize listener service with new user ID
    if (_notificationBloc != null) {
      _listenerService = NotificationListenerService(_notificationBloc!, userId);
      _listenerService?.startListening();
    }
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

  // Add this missing method
  void stopListening() {
    _listenerService?.stopListening();
    _currentUserId = null;
    _currentUserName = null;
    _currentUserEmail = null;
  }

  // Clean up when user logs out
  Future<void> cleanup() async {
    if (_currentUserId != null) {
      await unsubscribeFromTopics(_currentUserId!);
    }
    stopListening();
  }
}