import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceCenterServiceOffer {
  final String id;
  final String serviceCenterId;
  final String categoryId;
  final String serviceId;
  final String? tierId;
  final String servicePackageId;

  String? serviceCenterName;
  final List<String> makes;
  final Map<String, List<String>> models;
  final Map<String, List<String>> years;
  final Map<String, List<String>> fuelTypes;
  final Map<String, List<String>> displacements;
  final Map<String, List<String>> sizeClasses;

  final int duration; // minutes
  final double partPrice;
  final double partPriceMin;
  final double partPriceMax;
  final double labourPrice;
  final double labourPriceMin;
  final double labourPriceMax;
  final String serviceDescription;
  final bool active;

  final DateTime createdAt;
  final DateTime updatedAt;

  String? serviceName;

  ServiceCenterServiceOffer({
    required this.id,
    required this.serviceCenterId,
    required this.categoryId,
    required this.serviceId,
    required this.servicePackageId,
    this.tierId,
    this.serviceCenterName,
    required this.makes,
    required this.models,
    required this.years,
    required this.fuelTypes,
    required this.displacements,
    required this.sizeClasses,
    required this.duration,
    required this.partPrice,
    required this.partPriceMin,
    required this.partPriceMax,
    required this.labourPrice,
    required this.labourPriceMin,
    required this.labourPriceMax,
    required this.serviceDescription,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.serviceName,
  });

  factory ServiceCenterServiceOffer.fromFirestore(
      String id, Map<String, dynamic> data) {

    // convert to string
    String parseString(dynamic value, {String defaultValue = ''}) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      return value.toString();
    }

    // convert list to List<String>
    List<String> parseStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((e) => parseString(e)).toList();
      }
      return [];
    }

    // convert map values to Map<String, List<String>>
    Map<String, List<String>> parseStringMap(dynamic value) {
      if (value == null) return {};
      if (value is Map) {
        return value.map<String, List<String>>(
              (k, v) => MapEntry(
              parseString(k),
              parseStringList(v)
          ),
        );
      }
      return {};
    }

    double parseDouble(dynamic value, {double defaultValue = 0.0}) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        return double.tryParse(value) ?? defaultValue;
      }
      return defaultValue;
    }

    int parseInt(dynamic value, {int defaultValue = 0}) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) {
        return int.tryParse(value) ?? defaultValue;
      }
      return defaultValue;
    }

    return ServiceCenterServiceOffer(
      id: id,
      serviceCenterId: parseString(data['serviceCenterId']),
      categoryId: parseString(data['categoryId']),
      serviceId: parseString(data['serviceId']),
      servicePackageId: parseString(data['servicePackageId']),
      tierId: data['tierId'] != null ? parseString(data['tierId']) : null,

      serviceCenterName: parseString(data['serviceCenterName']),
      makes: parseStringList(data['makes']),
      models: parseStringMap(data['models']),
      years: parseStringMap(data['years']),
      fuelTypes: parseStringMap(data['fuelTypes']),
      displacements: parseStringMap(data['displacements']),
      sizeClasses: parseStringMap(data['sizeClasses']),

      duration: parseInt(data['duration']),

      partPrice: parseDouble(data['partPrice']),
      partPriceMin: parseDouble(data['partPriceMin']),
      partPriceMax: parseDouble(data['partPriceMax']),

      labourPrice: parseDouble(data['labourPrice']),
      labourPriceMin: parseDouble(data['labourPriceMin']),
      labourPriceMax: parseDouble(data['labourPriceMax']),

      serviceDescription: parseString(data['serviceDescription']),
      active: data['active'] ?? true,

      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'serviceCenterId': serviceCenterId,
      'categoryId': categoryId,
      'serviceId': serviceId,
      'servicePackageId': servicePackageId,
      'tierId': tierId,
      'makes': makes,
      'models': models,
      'years': years,
      'fuelTypes': fuelTypes,
      'displacements': displacements,
      'sizeClasses': sizeClasses,
      'duration': duration,
      'partPrice': partPrice,
      'partPriceMin': partPriceMin,
      'partPriceMax': partPriceMax,
      'labourPrice': labourPrice,
      'labourPriceMin': labourPriceMin,
      'labourPriceMax': labourPriceMax,
      'serviceDescription': serviceDescription,
      'active': active,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}