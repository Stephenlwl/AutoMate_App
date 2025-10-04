import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Key;
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:automate_application/model/service_center_service_package_offer_model.dart';

/// CryptoJS-compatible AES decryption
class CryptoJSCompat {
  static String decrypt(String encryptedBase64, String passphrase) {
    try {
      final encrypted = base64.decode(encryptedBase64);

      final prefix = utf8.decode(encrypted.sublist(0, 8));
      if (prefix != "Salted__") {
        throw Exception("Invalid data: missing Salted__ prefix");
      }

      final salt = encrypted.sublist(8, 16);
      final ciphertext = encrypted.sublist(16);

      final keyIv = _evpBytesToKey(32, 16, passphrase, salt);
      final key = keyIv.sublist(0, 32);
      final iv = keyIv.sublist(32, 48);

      final cipher = CBCBlockCipher(AESFastEngine())
        ..init(false, ParametersWithIV(KeyParameter(key), iv));

      final paddedPlaintext = _processBlocks(cipher, ciphertext);
      final plaintext = _pkcs7Unpad(paddedPlaintext);

      return utf8.decode(plaintext);
    } catch (e) {
      debugPrint("Decryption error: $e");
      return "";
    }
  }

  static Uint8List _evpBytesToKey(
    int keyLen,
    int ivLen,
    String passphrase,
    List<int> salt,
  ) {
    final pass = utf8.encode(passphrase);
    final data = <int>[];
    List<int> prev = [];

    while (data.length < keyLen + ivLen) {
      final d = md5.convert([...prev, ...pass, ...salt]).bytes;
      data.addAll(d);
      prev = d;
    }

    return Uint8List.fromList(data.sublist(0, keyLen + ivLen));
  }

  static Uint8List _processBlocks(BlockCipher cipher, List<int> input) {
    // convert List<int> to Uint8List
    final Uint8List inputBytes = Uint8List.fromList(input);

    final out = Uint8List(inputBytes.length);
    var offset = 0;

    while (offset < inputBytes.length) {
      offset += cipher.processBlock(inputBytes, offset, out, offset);
    }

    return out;
  }

  static List<int> _pkcs7Unpad(Uint8List bytes) {
    final padLen = bytes.last;
    return bytes.sublist(0, bytes.length - padLen);
  }
}

class ServiceCenter {
  final String id;
  final String email;
  final String name;
  final String serviceCenterPhoneNo;
  final String description;
  final List<String> images;
  final String addressLine1;
  final String? addressLine2;
  final String postalCode;
  final String city;
  final String state;
  double? latitude;
  double? longitude;
  double? distance;
  double rating;
  int reviewCount;
  List<String> services;
  List<ServicePackage> packages;
  final List<Map<String, dynamic>> specialClosures;
  final List<Map<String, dynamic>> operatingHours;
  final String serviceCenterPhoto;
  final String verificationStatus;
  final DateTime updatedAt;
  bool? isOnline;
  String? responseTime;

  set setRating(double newRating) {
    rating = newRating;
  }

  set setReviewCount(int newCount) {
    reviewCount = newCount;
  }

  ServiceCenter({
    required this.id,
    required this.email,
    required this.name,
    required this.serviceCenterPhoneNo,
    required this.description,
    required this.images,
    required this.addressLine1,
    this.addressLine2,
    required this.postalCode,
    required this.city,
    required this.state,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.reviewCount,
    this.distance,
    required this.specialClosures,
    required this.operatingHours,
    required this.serviceCenterPhoto,
    required this.verificationStatus,
    required this.updatedAt,
    this.services = const [],
    this.packages = const [],
    this.isOnline,
    this.responseTime,
  });

  factory ServiceCenter.fromFirestore(String id, Map<String, dynamic> data) {
    const secretKey = "AUTO_MATE_SECRET_KEY_256";

    double parseDouble(
      dynamic value,
      String fieldName, {
      double defaultValue = 0.0,
    }) {
      if (value == null) return defaultValue;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed == null) {
          debugPrint(
            "Warning: Could not parse '$value' as double for field '$fieldName'",
          );
        }
        return parsed ?? defaultValue;
      }
      debugPrint(
        "Warning: Unexpected type ${value.runtimeType} for field '$fieldName'",
      );
      return defaultValue;
    }

    int parseInt(dynamic value, String fieldName, {int defaultValue = 0}) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed == null) {
          debugPrint(
            "Warning: Could not parse '$value' as int for field '$fieldName'",
          );
        }
        return parsed ?? defaultValue;
      }
      debugPrint(
        "Warning: Unexpected type ${value.runtimeType} for field '$fieldName'",
      );
      return defaultValue;
    }

    String parseString(
      dynamic value,
      String fieldName, {
      String defaultValue = '',
    }) {
      if (value == null) return defaultValue;
      if (value is String) return value;
      if (value is int || value is double || value is bool) {
        return value.toString();
      }
      debugPrint(
        "Warning: Unexpected type ${value.runtimeType} for field '$fieldName'",
      );
      return defaultValue;
    }

    try {
      // Decrypt images when loading from Firestore
      List<String> decryptedImages = [];
      final rawImages = data['serviceCenterInfo']?['images'] ?? [];

      if (rawImages is List) {
        for (var item in rawImages) {
          if (item is String) {
            final decrypted = CryptoJSCompat.decrypt(item, secretKey);
            if (decrypted.isNotEmpty) {
              decryptedImages.add(decrypted);
            } else if (item.startsWith('http') || item.startsWith('data:')) {
              // keep original if it's already a URL or data URI (data:[<mediatype>][;base64],<data>)
              decryptedImages.add(item);
            }
          }
        }
      }

      String decryptedPhoto = '';
      final rawSvcMainImage = data['documents']?['serviceCenterPhoto'] ?? '';

      if (rawSvcMainImage != null && rawSvcMainImage is String) {
        final decrypted = CryptoJSCompat.decrypt(rawSvcMainImage, secretKey);
        if (decrypted.isNotEmpty) {
          decryptedPhoto = decrypted;
        } else if (rawSvcMainImage.startsWith('http') ||
            rawSvcMainImage.startsWith('data:')) {
          // keep original if it's already a URL or data URI
          decryptedPhoto = rawSvcMainImage;
        }
      }

      return ServiceCenter(
        id: id,
        email: parseString(data['adminInfo']?['email'], 'adminInfo.email'),
        name: parseString(
          data['serviceCenterInfo']?['name'],
          'serviceCenterInfo.name',
        ),
        serviceCenterPhoneNo: parseString(
          data['serviceCenterInfo']?['serviceCenterPhoneNo'],
          'serviceCenterInfo.serviceCenterPhoneNo',
        ),
        description: parseString(
          data['serviceCenterInfo']?['description'],
          'serviceCenterInfo.description',
        ),
        images: decryptedImages,
        addressLine1: parseString(
          data['serviceCenterInfo']?['address']?['addressLine1'],
          'serviceCenterInfo.address.addressLine1',
        ),
        addressLine2:
            data['serviceCenterInfo']?['address']?['addressLine2'] != null
                ? parseString(
                  data['serviceCenterInfo']['address']['addressLine2'],
                  'serviceCenterInfo.address.addressLine2',
                )
                : null,
        postalCode: parseString(
          data['serviceCenterInfo']?['address']?['postalCode'],
          'serviceCenterInfo.address.postalCode',
        ),
        city: parseString(
          data['serviceCenterInfo']?['address']?['city'],
          'serviceCenterInfo.address.city',
        ),
        state: parseString(
          data['serviceCenterInfo']?['address']?['state'],
          'serviceCenterInfo.address.state',
        ),
        latitude: (data['serviceCenterInfo']?['latitude'] as num?)?.toDouble(),
        longitude:
            (data['serviceCenterInfo']?['longitude'] as num?)?.toDouble(),
        rating: parseDouble(data['rating'], 'rating', defaultValue: 0.0),
        reviewCount: parseInt(
          data['reviewCount'],
          'reviewCount',
          defaultValue: 0,
        ),
        specialClosures: List<Map<String, dynamic>>.from(
          data['specialClosures'] ?? [],
        ),
        operatingHours: List<Map<String, dynamic>>.from(
          data['operatingHours'] ?? [],
        ),
        serviceCenterPhoto: decryptedPhoto,
        verificationStatus: parseString(
          data['verification']?['status'],
          'verification.status',
        ),
        updatedAt: (data['updatedAt'] as Timestamp).toDate(),
        distance: null,
        services: [],
        packages: [],
        isOnline: data['isOnline'] ?? false,
        responseTime: data['responseTime'] ?? null,
      );
    } catch (e, stackTrace) {
      debugPrint(
        "Error in ServiceCenter.fromFirestore for document $id: $e\n$stackTrace\nDocument data: $data",
      );
      rethrow;
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'serviceCenterInfo': {
        'name': name,
        'serviceCenterPhoneNo': serviceCenterPhoneNo,
        'description': description,
        'images': images,
        'longitude': longitude,
        'latitude': latitude,
        'address': {
          'addressLine1': addressLine1,
          if (addressLine2 != null) 'addressLine2': addressLine2,
          'postalCode': postalCode,
          'city': city,
          'state': state,
        },
      },
      'rating': rating,
      'reviewCount': reviewCount,
      'specialClosures': specialClosures,
      'operatingHours': operatingHours,
      'documents': {'serviceCenterPhoto': serviceCenterPhoto},
      'verification': {'status': verificationStatus},
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
