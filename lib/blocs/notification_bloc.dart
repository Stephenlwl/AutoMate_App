import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:automate_application/model/notification_model.dart';

abstract class NotificationEvent {}

class NewNotificationEvent extends NotificationEvent {
  final NotificationModel notification;
  NewNotificationEvent(this.notification);
}

class MarkAsReadEvent extends NotificationEvent {
  final String notificationId;
  MarkAsReadEvent(this.notificationId);
}

class LoadNotificationsEvent extends NotificationEvent {}

class ClearAllNotificationsEvent extends NotificationEvent {}

class NotificationState {
  final List<NotificationModel> notifications;
  final int unreadCount;
  final bool isLoading;

  NotificationState({
    required this.notifications,
    required this.unreadCount,
    this.isLoading = false,
  });

  NotificationState copyWith({
    List<NotificationModel>? notifications,
    int? unreadCount,
    bool? isLoading,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  NotificationBloc() : super(NotificationState(
    notifications: [],
    unreadCount: 0,
  )) {
    on<NewNotificationEvent>(_onNewNotification);
    on<MarkAsReadEvent>(_onMarkAsRead);
    on<LoadNotificationsEvent>(_onLoadNotifications);
    on<ClearAllNotificationsEvent>(_onClearAllNotifications);
  }

  void _onNewNotification(NewNotificationEvent event, Emitter<NotificationState> emit) {
    final updatedNotifications = [event.notification, ...state.notifications];
    final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

    emit(state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
    ));
  }

  void _onMarkAsRead(MarkAsReadEvent event, Emitter<NotificationState> emit) {
    final updatedNotifications = state.notifications.map((notification) {
      if (notification.id == event.notificationId) {
        return notification.copyWith(isRead: true);
      }
      return notification;
    }).toList();

    final unreadCount = updatedNotifications.where((n) => !n.isRead).length;

    emit(state.copyWith(
      notifications: updatedNotifications,
      unreadCount: unreadCount,
    ));
  }

  void _onLoadNotifications(LoadNotificationsEvent event, Emitter<NotificationState> emit) {
    // Load from local storage or Firestore
    // This is a simplified version
  }

  void _onClearAllNotifications(ClearAllNotificationsEvent event, Emitter<NotificationState> emit) {
    emit(state.copyWith(
      notifications: [],
      unreadCount: 0,
    ));
  }
}