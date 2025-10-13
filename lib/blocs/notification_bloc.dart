import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automate_application/model/notification_model.dart';
import 'dart:convert';

abstract class NotificationEvent {}

class NewNotificationEvent extends NotificationEvent {
  final NotificationModel notification;
  final bool shouldShowPopup; // Control whether to show popup
  NewNotificationEvent(this.notification, {this.shouldShowPopup = true});
}

class MarkAsReadEvent extends NotificationEvent {
  final String notificationId;
  MarkAsReadEvent(this.notificationId);
}

class LoadNotificationsEvent extends NotificationEvent {}

class ClearAllNotificationsEvent extends NotificationEvent {}

class MarkAllAsReadEvent extends NotificationEvent {}

class NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool isLoading;
  final List<String> shownNotificationIds; // Track shown notifications

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

  NotificationBloc() : super(NotificationState(
    notifications: [],
    unreadCount: 0,
    shownNotificationIds: [],
  )) {
    on<NewNotificationEvent>(_onNewNotification);
    on<MarkAsReadEvent>(_onMarkAsRead);
    on<LoadNotificationsEvent>(_onLoadNotifications);
    on<ClearAllNotificationsEvent>(_onClearAllNotifications);
    on<MarkAllAsReadEvent>(_onMarkAllAsRead);

    // Load persisted data when bloc is created
    _loadPersistedData();
  }

  void _onNewNotification(NewNotificationEvent event, Emitter<NotificationState> emit) async {
    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    // Check if notification already exists or has been shown before
    final existingIndex = state.notifications.indexWhere((n) =>
    n.id == event.notification.id ||
        _isDuplicateNotification(n, event.notification)
    );

    // Check if this notification has already been shown to user
    final hasBeenShown = state.shownNotificationIds.contains(event.notification.id);

    List<NotificationModel> updatedNotifications;
    List<String> updatedShownIds = List.from(state.shownNotificationIds);

    if (existingIndex != -1) {
      // Replace existing notification with the new one
      updatedNotifications = List.from(state.notifications);
      updatedNotifications[existingIndex] = event.notification;
    } else {
      // Add new notification to the beginning
      updatedNotifications = [event.notification, ...state.notifications];

      // Mark as shown if it's a popup notification
      if (event.shouldShowPopup && !hasBeenShown) {
        updatedShownIds.add(event.notification.id);
      }

      // Limit notifications to last 50
      if (updatedNotifications.length > 50) {
        updatedNotifications = updatedNotifications.sublist(0, 50);
      }
    }

    final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

    final newState = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
      shownNotificationIds: updatedShownIds,
    );

    // Persist the state
    _persistState(newState);

    emit(newState);
  }

  bool _isDuplicateNotification(NotificationModel existing, NotificationModel newNotification) {
    // Check if it's the same type and has the same key data
    if (existing.type != newNotification.type) return false;

    switch (existing.type) {
      case 'service_booking':
        final existingBookingId = existing.data['bookingId'];
        final newBookingId = newNotification.data['bookingId'];
        return existingBookingId != null && existingBookingId == newBookingId;

      case 'towing_request':
        final existingRequestId = existing.data['requestId'];
        final newRequestId = newNotification.data['requestId'];
        return existingRequestId != null && existingRequestId == newRequestId;

      default:
      // For other types, check title and body
        return existing.title == newNotification.title &&
            existing.body == newNotification.body;
    }
  }

  void _onMarkAsRead(MarkAsReadEvent event, Emitter<NotificationState> emit) async {
    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final updatedNotifications = state.notifications.map((notification) {
      if (notification.id == event.notificationId) {
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
    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final updatedNotifications = state.notifications.map((notification) {
      return notification.copyWith(isRead: true);
    }).toList();

    final newState = state.copyWith(
      notifications: updatedNotifications,
      unreadCount: 0,
    );

    _persistState(newState);
    emit(newState);
  }

  void _onLoadNotifications(LoadNotificationsEvent event, Emitter<NotificationState> emit) async {
    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }
    // State is already loaded, no need to emit
  }

  void _onClearAllNotifications(ClearAllNotificationsEvent event, Emitter<NotificationState> emit) async {
    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final newState = state.copyWith(
      notifications: [],
      unreadCount: 0,
      shownNotificationIds: [],
    );

    _persistState(newState);
    emit(newState);
  }

  // Persistence methods
  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load shown notification IDs
      final shownIds = prefs.getStringList(_shownNotificationsKey) ?? [];

      // Load saved notifications
      final notificationsJson = prefs.getStringList(_notificationsKey) ?? [];
      final notifications = notificationsJson.map((json) {
        try {
          return NotificationModel.fromJson(Map<String, dynamic>.from(jsonDecode(json)));
        } catch (e) {
          return null;
        }
      }).whereType<NotificationModel>().toList();

      // Update state with persisted data
      emit(state.copyWith(
        notifications: notifications,
        unreadCount: notifications.where((n) => !n.isRead).length,
        shownNotificationIds: shownIds,
      ));
    } catch (e) {
      print('Error loading persisted notifications: $e');
    }
  }

  Future<void> _persistState(NotificationState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save shown notification IDs
      await prefs.setStringList(_shownNotificationsKey, state.shownNotificationIds);

      // Save notifications
      final notificationsJson = state.notifications
          .map((notification) => jsonEncode(notification.toJson()))
          .toList();
      await prefs.setStringList(_notificationsKey, notificationsJson);
    } catch (e) {
      print('Error persisting notifications: $e');
    }
  }

  // Helper method to check if a notification should show popup
  bool shouldShowPopup(NotificationModel notification) {
    return !state.shownNotificationIds.contains(notification.id) && !notification.isRead;
  }

  // Method to mark notification as shown (call this when popup is displayed)
  void markNotificationAsShown(String notificationId) {
    if (!state.shownNotificationIds.contains(notificationId)) {
      final updatedShownIds = [...state.shownNotificationIds, notificationId];
      final newState = state.copyWith(shownNotificationIds: updatedShownIds);
      _persistState(newState);
      emit(newState);
    }
  }
}