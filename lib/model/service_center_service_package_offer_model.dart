import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ServicePackage {
  final String id;
  final String serviceCenterId;
  String? serviceCenterName;
  final String name;
  final String description;
  final List<PackageService> services;
  final double? fixedPrice;
  final double? minPrice;
  final double? maxPrice;
  final int estimatedDuration;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServicePackage({
    required this.id,
    required this.serviceCenterId,
    this.serviceCenterName,
    required this.name,
    required this.description,
    required this.services,
    this.fixedPrice,
    this.minPrice,
    this.maxPrice,
    required this.estimatedDuration,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServicePackage.fromFirestore(String id, Map<String, dynamic> data) {
    final servicesData = data['services'] as List<dynamic>? ?? [];
    final services = servicesData.map((service) => PackageService.fromMap(service)).toList();

    return ServicePackage(
      id: id,
      serviceCenterId: data['serviceCenterId'] ?? '',
      serviceCenterName: data['serviceCenterName'] ?? '',
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      services: services,
      fixedPrice: data['fixedPrice']?.toDouble(),
      minPrice: data['minPrice']?.toDouble(),
      maxPrice: data['maxPrice']?.toDouble(),
      estimatedDuration: data['estimatedDuration'] ?? 60,
      active: data['active'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class PackageService {
  final String serviceId;
  final String serviceName;
  final String categoryId;
  final String categoryName;
  final int duration;
  final double labourPrice;
  final double partPrice;
  final double labourPriceMin;
  final double labourPriceMax;
  final double partPriceMin;
  final double partPriceMax;

  PackageService({
    required this.serviceId,
    required this.serviceName,
    required this.categoryId,
    required this.categoryName,
    required this.duration,
    this.labourPrice = 0,
    this.partPrice = 0,
    this.labourPriceMin = 0,
    this.labourPriceMax = 0,
    this.partPriceMin = 0,
    this.partPriceMax = 0,
  });

  factory PackageService.fromMap(Map<String, dynamic> map) {
    return PackageService(
      serviceId: map['serviceId'] ?? '',
      serviceName: map['serviceName'] ?? '',
      categoryId: map['categoryId'] ?? '',
      categoryName: map['categoryName'] ?? '',
      duration: map['duration'] ?? 0,
      labourPrice: (map['labourPrice'] ?? 0).toDouble(),
      partPrice: (map['partPrice'] ?? 0).toDouble(),
      labourPriceMin: (map['labourPriceMin'] ?? 0).toDouble(),
      labourPriceMax: (map['labourPriceMax'] ?? 0).toDouble(),
      partPriceMin: (map['partPriceMin'] ?? 0).toDouble(),
      partPriceMax: (map['partPriceMax'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'serviceName': serviceName,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'duration': duration,
      'labourPrice': labourPrice,
      'partPrice': partPrice,
      'labourPriceMin': labourPriceMin,
      'labourPriceMax': labourPriceMax,
      'partPriceMin': partPriceMin,
      'partPriceMax': partPriceMax,
    };
  }
}

class ServiceOffer {
  final String serviceId;
  final String serviceName;
  final String description;
  final String categoryName;
  final List<ServiceCenterServiceOffer> offers;

  ServiceOffer({
    required this.serviceId,
    required this.serviceName,
    required this.description,
    required this.categoryName,
    required this.offers,
  });
}