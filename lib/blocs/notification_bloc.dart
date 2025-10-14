import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:automate_application/model/notification_model.dart';
import 'dart:convert';

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

class ClearAllNotificationsEvent extends NotificationEvent {}

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
    on<ClearAllNotificationsEvent>(_onClearAllNotifications);
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
    // First check if notification belongs to current user
    if (event.notification.userId != currentUserId) {
      return;
    }

    // Load data if not already loaded
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final existingIndex = state.notifications.indexWhere((n) =>
    n.id == event.notification.id ||
        _isDuplicateNotification(n, event.notification)
    );

    final hasBeenShown = state.shownNotificationIds.contains(event.notification.id);

    List<NotificationModel> updatedNotifications;
    List<String> updatedShownIds = List.from(state.shownNotificationIds);

    if (existingIndex != -1) {
      updatedNotifications = List.from(state.notifications);
      updatedNotifications[existingIndex] = event.notification;
    } else {
      updatedNotifications = [event.notification, ...state.notifications];

      if (event.shouldShowPopup && !hasBeenShown) {
        updatedShownIds.add(event.notification.id);
      }

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

    _persistState(newState);
    emit(newState);
  }

  bool _isDuplicateNotification(NotificationModel existing, NotificationModel newNotification) {
    if (existing.type != newNotification.type) return false;

    final existingUserId = existing.data['userId'];
    final newUserId = newNotification.data['userId'];
    if (existingUserId != null && newUserId != null && existingUserId != newUserId) {
      return false;
    }

    switch (existing.type) {
      case 'service_booking':
        final existingBookingId = existing.data['bookingId'];
        final newBookingId = newNotification.data['bookingId'];
        return existingBookingId != null && existingBookingId == newBookingId;

      case 'towing_request':
        final existingRequestId = existing.data['requestId'];
        final newRequestId = newNotification.data['requestId'];
        return existingRequestId != null && existingRequestId == newRequestId;

      case 'service_reminder':
        final existingVehicle = existing.data['vehicleInfo'];
        final newVehicle = newNotification.data['vehicleInfo'];
        final existingReminderType = existing.data['reminderType'];
        final newReminderType = newNotification.data['reminderType'];
        return existingVehicle == newVehicle && existingReminderType == newReminderType;

      default:
        return existing.title == newNotification.title &&
            existing.body == newNotification.body;
    }
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

  void _onClearAllNotifications(ClearAllNotificationsEvent event, Emitter<NotificationState> emit) async {
    if (state.notifications.isEmpty && state.shownNotificationIds.isEmpty) {
      await _loadPersistedData();
    }

    final userNotifications = state.notifications.where((n) => n.userId == currentUserId).toList();
    final userShownIds = state.shownNotificationIds.where((id) {
      final notification = state.notifications.firstWhere((n) => n.id == id, orElse: () => NotificationModel(
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

    final newState = state.copyWith(
      notifications: state.notifications.where((n) => n.userId != currentUserId).toList(),
      unreadCount: 0,
      shownNotificationIds: state.shownNotificationIds.where((id) => !userShownIds.contains(id)).toList(),
    );

    _persistState(newState);
    emit(newState);
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