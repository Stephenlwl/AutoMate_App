import 'package:cloud_firestore/cloud_firestore.dart';
class Review {
  final String id;
  final String serviceCenterId;
  final String serviceCenterName;
  final String userId;
  final String userName;
  final String userEmail;
  final String type;
  final double rating;
  final String? comment;
  final DateTime reviewedAt;
  final DateTime createdAt;
  final double totalAmount;
  final Map<String, dynamic> vehicleInfo;
  final String? towingType;
  final List<dynamic>? services;
  final List<dynamic>? packages;
  final String? selectionType;
  final String bookingId;
  final String status;

  Review({
    required this.id,
    required this.serviceCenterId,
    required this.serviceCenterName,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.type,
    required this.rating,
    this.comment,
    required this.reviewedAt,
    required this.createdAt,
    required this.totalAmount,
    required this.vehicleInfo,
    this.towingType,
    this.services,
    this.packages,
    this.selectionType,
    required this.bookingId,
    required this.status,
  });

  factory Review.fromFirestore(String id, Map<String, dynamic> data) {
    return Review(
      id: id,
      serviceCenterId: data['serviceCenterId'] ?? '',
      serviceCenterName: data['serviceCenterName'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anonymous',
      userEmail: data['userEmail'] ?? '',
      type: data['type'] ?? 'service',
      rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      comment: data['comment'],
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      vehicleInfo: Map<String, dynamic>.from(data['vehicleInfo'] ?? {}),
      towingType: data['towingType'],
      services: data['services'],
      packages: data['packages'],
      selectionType: data['selectionType'],
      bookingId: data['bookingId'] ?? '',
      status: data['status'] ?? 'approved',
    );
  }
}