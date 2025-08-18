import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CarOwnerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> registerCarOwner({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String brand,
    required String model,
    required String year,
    required String vin,
    required String plateNumber,
    required dynamic icImage,
    required dynamic selfieImage,
    required dynamic vocImage,
    required bool isWeb,
  }) async {

     // Validate size limit to 500 KB
    // _validateImageSize(icImage, isWeb, 'IC');
    // _validateImageSize(selfieImage, isWeb, 'Selfie');
    // _validateImageSize(vocImage, isWeb, 'VOC');

    // Encode images to base64
    String icUrl = _convertToBase64(icImage, isWeb);
    String selfieUrl = _convertToBase64(selfieImage, isWeb);
    String vocUrl = _convertToBase64(vocImage, isWeb);

    final userId = DateTime.now().millisecondsSinceEpoch.toString();
    final hashedPassword = _hashPassword(password);

    // Save data to Realtime Database
    final ref = _firestore.collection('car_owners').doc(userId);
    await ref.set({
      'userId': userId,
      'name': name,
      'email': email,
      'password': hashedPassword,
      'phone': phone,
      'documents': {
        'icUrl': 'data:image/jpeg;base64,' + icUrl,
        'selfieUrl': 'data:image/jpeg;base64,' + selfieUrl,
        'vocUrl': 'data:image/jpeg;base64,' + vocUrl,
      },
      'verification': {
        'status': 'pending',
        'rejectionReason': '',
      },
      'vehicles': [
        {
          'brand': brand,
          'model': model,
          'year': year,
          'vin': vin,
          'plate_number': plateNumber,
          'status': 'pending',
        }
      ],
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // void _validateImageSize(dynamic file, bool isWeb, String label) {
  //   int sizeInBytes;
  //   if (isWeb) {
  //     sizeInBytes = (file as Uint8List).lengthInBytes;
  //   } else {
  //     sizeInBytes = (file as File).lengthSync();
  //   }
  //
  //   const int maxSize = 500 * 1024; // 500 KB
  //
  //   if (sizeInBytes > maxSize) {
  //     throw Exception('$label image size must be less than 500 KB.');
  //   }
  // }

  String _convertToBase64(dynamic file, bool isWeb) {
    Uint8List bytes;

    if (isWeb) {
      bytes = file as Uint8List;
    } else {
      bytes = (file as File).readAsBytesSync();
    }

    return base64Encode(bytes);
  }
}
