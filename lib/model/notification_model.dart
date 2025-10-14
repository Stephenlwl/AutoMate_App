import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final bool isRead;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.data,
    required this.timestamp,
    this.isRead = false,
  });

  factory NotificationModel.fromRemoteMessage(RemoteMessage message, {required String currentUserId}) {
    final messageUserId = message.data['userId'] ?? currentUserId;

    return NotificationModel(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: messageUserId,
      title: message.notification?.title ?? 'AutoMate',
      body: message.notification?.body ?? '',
      type: message.data['type'] ?? 'system',
      data: message.data,
      timestamp: DateTime.now(),
    );
  }

  factory NotificationModel.create({
    required String userId,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic>? data,
    String? id,
  }) {
    return NotificationModel(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userId,
      title: title,
      body: body,
      type: type,
      data: data ?? {},
      timestamp: DateTime.now(),
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: json['type'] as String,
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  String toJsonString() {
    return json.encode(toJson());
  }

  NotificationModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? body,
    String? type,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  bool get isServiceReminder => type == 'service_reminder';
  bool get isServiceBooking => type == 'service_booking';
  bool get isTowingRequest => type == 'towing_request';

  String get reminderDetails {
    if (!isServiceReminder) return '';

    final reminderType = data['reminderType'] ?? '';
    final serviceType = data['serviceType'] ?? '';
    final vehicleInfo = data['vehicleInfo'] ?? '';

    switch (reminderType) {
      case 'mileage':
        final current = data['currentMileage'] ?? 0;
        final due = data['dueMileage'] ?? 0;
        return 'Mileage: $current/$due km';
      case 'date':
        final days = data['daysUntilDue'] ?? 0;
        return 'Due in $days days';
      case 'overdue':
        final days = data['daysOverdue'] ?? 0;
        return 'Overdue by $days days';
      default:
        return '';
    }
  }

  String get vehicleInfo {
    return data['vehicleInfo']?.toString() ??
        data['vehicle']?.toString() ??
        'Your Vehicle';
  }

  String get serviceType {
    return data['serviceType']?.toString() ?? 'Service';
  }
}