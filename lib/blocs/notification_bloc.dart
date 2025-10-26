import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automate_application/model/notification_model.dart';
import 'dart:convert';
import '../services/notification_service.dart';

abstract class NotificationEvent {}

class NewNotificationEvent extends NotificationEvent {
  final NotificationModel notification;
  final bool shouldShowPopup;
  NewNotificationEvent(this.notification, {this.shouldShowPopup = true});
}

class MarkAsReadEvent extends NotificationEvent {
  final String notificationId;
  MarkAsReadEvent(this.notificationId);
}

class LoadNotificationsEvent extends NotificationEvent {}

class MarkAllAsReadEvent extends NotificationEvent {}

class NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool isLoading;
  final List<String> shownNotificationIds;

  NotificationState({
    required this.notifications,
    required this.unreadCount,
    this.isLoading = false,
    List<String>? shownNotificationIds,
  }) : shownNotificationIds = shownNotificationIds ?? [];

  NotificationState copyWith({
    List<NotificationModel>? notifications,
    int? unreadCount,
    bool? isLoading,
    List<String>? shownNotificationIds,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      shownNotificationIds: shownNotificationIds ?? this.shownNotificationIds,
    );
  }
}

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  static const String _shownNotificationsKey = 'shown_notifications';
  static const String _notificationsKey = 'saved_notifications';

  String currentUserId;

  NotificationBloc({required this.currentUserId}) : super(NotificationState(
    notifications: [],
    unreadCount: 0,
    shownNotificationIds: [],
  )) {
    on<NewNotificationEvent>(_onNewNotification);
    on<MarkAsReadEvent>(_onMarkAsRead);
    on<LoadNotificationsEvent>(_onLoadNotifications);
    on<MarkAllAsReadEvent>(_onMarkAllAsRead);

    _loadPersistedData();
  }

  void updateUserId(String newUserId) {
    if (newUserId != currentUserId) {
      currentUserId = newUserId;
      add(LoadNotificationsEvent());
    }
  }

  void _onNewNotification(NewNotificationEvent event, Emitter<NotificationState> emit) async {
    if (event.notification.userId != currentUserId) {
      return;
    }

    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final isDuplicate = state.notifications.any((existing) =>
        _isStrictDuplicate(existing, event.notification)
    );
    if (isDuplicate) {
      return;
    }

    List<NotificationModel> updatedNotifications;
    List<String> updatedShownIds = List.from(state.shownNotificationIds);

    updatedNotifications = [event.notification, ...state.notifications];

    final shouldShowPopup = event.shouldShowPopup &&
        !updatedShownIds.contains(event.notification.id) &&
        !_isAlreadyShown(event.notification);

    if (shouldShowPopup) {
      // only service_reminder type repeated
      final isServiceReminder = event.notification.type == 'service_reminder';
      final hasBeenShownBefore = updatedShownIds.contains(event.notification.id);

      if (isServiceReminder || !hasBeenShownBefore) {
        updatedShownIds.add(event.notification.id);
        _showLocalNotification(event.notification);
      }
    }

    if (updatedNotifications.length > 50) {
      updatedNotifications = updatedNotifications.sublist(0, 50);
    }

    // Calculate unread count only for current user
    final userNotifications = updatedNotifications.where((n) => n.userId == currentUserId);
    final unreadCount = userNotifications.where((n) => !n.isRead).length;

    final newState = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
      shownNotificationIds: updatedShownIds,
    );

    _persistState(newState);
    emit(newState);
  }

  bool _isAlreadyShown(NotificationModel notification) {
    // service_booking and towing_request check if similar notification was already shown
    if (notification.type == 'service_booking' || notification.type == 'towing_request') {
      return state.shownNotificationIds.any((shownId) {
        final shownNotification = state.notifications.firstWhere(
              (n) => n.id == shownId,
          orElse: () => NotificationModel(
            id: '',
            title: '',
            body: '',
            type: '',
            timestamp: DateTime.now(),
            data: {},
            userId: '',
          ),
        );

        // Check if it's the same type and has the same booking orrequest ID
        if (shownNotification.type == notification.type) {
          final existingId = shownNotification.data['bookingId'] ?? shownNotification.data['requestId'];
          final newId = notification.data['bookingId'] ?? notification.data['requestId'];
          return existingId == newId && existingId != null;
        }
        return false;
      });
    }
    return state.shownNotificationIds.contains(notification.id);
  }

  Future<void> _showLocalNotification(NotificationModel notification) async {
    try {
      final notificationService = NotificationService();

      // Use the centralized notification service
      await notificationService.showLocalNotification(notification);
    } catch (e) {
      debugPrint('Error showing local notification from bloc: $e');
    }
  }

  bool _isStrictDuplicate(NotificationModel existing, NotificationModel newNotification) {
    if (existing.userId != newNotification.userId) return false;
    if (existing.id == newNotification.id) return true;

    if (existing.type == 'service_booking' || existing.type == 'towing_request') {
      final existingId = existing.data['bookingId'] ?? existing.data['requestId'];
      final newId = newNotification.data['bookingId'] ?? newNotification.data['requestId'];
      return existingId != null && newId != null && existingId == newId;
    }

    if (existing.type == 'service_reminder') {
      final existingVehicle = existing.data['vehicleInfo'];
      final newVehicle = newNotification.data['vehicleInfo'];
      final existingReminderType = existing.data['reminderType'];
      final newReminderType = newNotification.data['reminderType'];
      final timeDifference = existing.timestamp.difference(newNotification.timestamp).abs();

      return existingVehicle == newVehicle &&
          existingReminderType == newReminderType &&
          timeDifference.inHours < 24;
    }

    return false;
  }

  void _onMarkAsRead(MarkAsReadEvent event, Emitter<NotificationState> emit) async {
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final updatedNotifications = state.notifications.map((notification) {
      if (notification.id == event.notificationId && notification.userId == currentUserId) {
        return notification.copyWith(isRead: true);
      }
      return notification;
    }).toList();

    final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

    final newState = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
    );

    _persistState(newState);
    emit(newState);
  }

  void _onMarkAllAsRead(MarkAllAsReadEvent event, Emitter<NotificationState> emit) async {
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final updatedNotifications = state.notifications.map((notification) {
      if (notification.userId == currentUserId) {
        return notification.copyWith(isRead: true);
      }
      return notification;
    }).toList();

    final newState = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: 0,
    );

    _persistState(newState);
    emit(newState);
  }

  void _onLoadNotifications(LoadNotificationsEvent event, Emitter<NotificationState> emit) async {
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }
  }

  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shownIds = prefs.getStringList(_shownNotificationsKey) ?? [];
      final notificationsJson = prefs.getStringList(_notificationsKey) ?? [];

      final allNotifications = notificationsJson.map((json) {
        try {
          return NotificationModel.fromJson(Map<String, dynamic>.from(jsonDecode(json)));
        } catch (e) {
          return null;
        }
      }).whereType<NotificationModel>().toList();

      // Filter notifications by current user
      final userNotifications = allNotifications.where((n) => n.userId == currentUserId).toList();
      final userShownIds = shownIds.where((id) {
        final notification = allNotifications.firstWhere((n) => n.id == id, orElse: () => NotificationModel(
          id: '',
          title: '',
          body: '',
          type: '',
          timestamp: DateTime.now(),
          data: {},
          userId: '',
        ));
        return notification.userId == currentUserId;
      }).toList();

      emit(state.copyWith(
        notifications: userNotifications,
        unreadCount: userNotifications.where((n) => !n.isRead).length,
        shownNotificationIds: userShownIds,
      ));
    } catch (e) {
      print('Error loading persisted notifications: $e');
    }
  }

  Future<void> _persistState(NotificationState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setStringList(_shownNotificationsKey, state.shownNotificationIds);

      final notificationsJson = state.notifications
          .map((notification) => jsonEncode(notification.toJson()))
          .toList();
      await prefs.setStringList(_notificationsKey, notificationsJson);
    } catch (e) {
      print('Error persisting notifications: $e');
    }
  }

  bool shouldShowPopup(NotificationModel notification) {
    return notification.userId == currentUserId &&
        !state.shownNotificationIds.contains(notification.id) &&
        !notification.isRead;
  }

  void markNotificationAsShown(String notificationId) {
    if (!state.shownNotificationIds.contains(notificationId)) {
      final updatedShownIds = [...state.shownNotificationIds, notificationId];
      final newState = state.copyWith(shownNotificationIds: updatedShownIds);
      _persistState(newState);
      emit(newState);
    }
  }
}