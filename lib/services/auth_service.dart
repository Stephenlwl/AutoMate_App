import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class AuthService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? currentUserId;

  // AES-256 requires a 32-char secret key
  final String _secretKey = "X9f@3LpZ7qW!m2CkT8r#Jd6vNb^Hs4Y0";
  late final encrypt.Key key;
  late final encrypt.Encrypter encrypter;

  AuthService() {
    key = encrypt.Key.fromUtf8(_secretKey);
    encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );
  }

  /// Generate random salt (16 bytes)
  Uint8List _generateSalt([int length = 16]) {
    final rand = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rand.nextInt(256)),
    );
  }

  /// Hash password using PBKDF2-like method
  String _hashPassword(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    final hmac = Hmac(sha256, salt);

    var digest = hmac.convert(passwordBytes);
    for (int i = 1; i < 10000; i++) {
      digest = hmac.convert(digest.bytes);
    }

    return base64Encode(digest.bytes);
  }

  /// Verify password using stored salt + stored hash
  bool _verifyPassword(
      String password,
      String storedHash,
      String storedSaltBase64,
      ) {
    final salt = base64Decode(storedSaltBase64);
    final recomputedHash = _hashPassword(password, salt);
    return recomputedHash == storedHash;
  }

  /// Encrypt images (convert to base64 first, then encrypt)
  Future<Map<String, String>> encryptImage(File file) async {
    try {
      // Detect MIME type
      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = "image/jpeg"; // default
      if (ext == "png") mimeType = "image/png";

      // Convert bytes to base64 string
      final bytes = await file.readAsBytes();
      final base64Text = base64Encode(bytes);

      // Generate random IV (16 bytes)
      final iv = encrypt.IV.fromLength(16);

      // Encrypt base64 string
      final encrypted = encrypter.encrypt(base64Text, iv: iv);

      return {
        "encrypted": encrypted.base64,
        "iv": base64Encode(iv.bytes),
        "mimeType": mimeType,
      };
    } catch (e) {
      throw Exception("Image encryption failed: $e");
    }
  }

  Future<bool> checkEmailExists(String email) async {
    try {
      final query = await _firestore
          .collection('car_owners')
          .where('email', isEqualTo: email)
          .where('verification.status', isEqualTo: 'approved')
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      print("Error checking email: $e");
      return false;
    }
  }

  Future<String?> registerCarOwner({
    required String name,
    required String email,
    required String role,
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
  }) async {
    try {
      final existingUser = await _firestore
          .collection('car_owners')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (existingUser.docs.isNotEmpty) {
        final doc = existingUser.docs.first;
        final userData = doc.data();
        final verification = userData['verification'] ?? {};
        final status = verification['status'] ?? '';

        if (status == 'approved') {
          throw Exception("This email is already registered. Please log in.");
        } else if (status == 'pending') {
          return 'pending';
        } else if (status == 'rejected') {
          // Handle resubmission for rejected user
          final salt = _generateSalt();
          final hashedPassword = _hashPassword(password, salt);

          final icData = await encryptImage(icImage);
          final selfieData = await encryptImage(selfieImage);
          final vocData = await encryptImage(vocImage);

          await doc.reference.update({
            'name': name,
            'password': hashedPassword,
            'salt': base64Encode(salt),
            'role': role,
            'phone': phone,
            'documents': {
              'icUrl': icData["encrypted"],
              'icType': icData["mimeType"],
              'icIv': icData["iv"],
              'selfieUrl': selfieData["encrypted"],
              'selfieType': selfieData["mimeType"],
              'selfieIv': selfieData["iv"],
              'vocUrl': vocData["encrypted"],
              'vocType': vocData["mimeType"],
              'vocIv': vocData["iv"],
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
              },
            ],
            'updated_at': FieldValue.serverTimestamp(),
          });

          print("Rejected user resubmitted: ${doc.id}");
          return 'pending';
        }
      }

      // Validate required files
      if (icImage == null || selfieImage == null || vocImage == null) {
        throw Exception("All document images are required");
      }

      // Generate unique salt per user
      final salt = _generateSalt();
      final hashedPassword = _hashPassword(password, salt);

      // Encrypt images
      final icData = await encryptImage(icImage);
      final selfieData = await encryptImage(selfieImage);
      final vocData = await encryptImage(vocImage);

      // Create document reference to get the ID
      final docRef = _firestore.collection('car_owners').doc();

      await docRef.set({
        'id': docRef.id,
        'name': name,
        'email': email,
        'password': hashedPassword,
        'salt': base64Encode(salt),
        'role': role,
        'phone': phone,
        'documents': {
          'icUrl': icData["encrypted"],
          'icType': icData["mimeType"],
          'icIv': icData["iv"],
          'selfieUrl': selfieData["encrypted"],
          'selfieType': selfieData["mimeType"],
          'selfieIv': selfieData["iv"],
          'vocUrl': vocData["encrypted"],
          'vocType': vocData["mimeType"],
          'vocIv': vocData["iv"],
        },
        'verification': {'status': 'pending', 'rejectionReason': ''},
        'vehicles': [
          {
            'brand': brand,
            'model': model,
            'year': year,
            'vin': vin,
            'plate_number': plateNumber,
            'status': 'pending',
          },
        ],
        'created_at': FieldValue.serverTimestamp(),
      });

      print("Car owner registered successfully with ID: ${docRef.id}");
      return 'success';
    } catch (e) {
      print("Registration error: $e");
      if (e.toString().contains("already registered")) {
        rethrow;
      } else {
        throw Exception("Registration failed: $e");
      }
    }
  }

  Future<AuthResult> loginCarOwner({
    required String email,
    required String password,
  }) async {
    try {
      final query = await _firestore
          .collection('car_owners')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return AuthResult(
          success: false,
          errorMessage: "Invalid email or password",
        );
      }

      final doc = query.docs.first;
      final data = doc.data();

      // Verify password with PBKDF2 + salt
      String storedPassword = data['password'] ?? '';
      String storedSalt = data['salt'] ?? '';

      if (storedPassword.isEmpty || storedSalt.isEmpty) {
        return AuthResult(
          success: false,
          errorMessage: "Account data is corrupted. Please contact support.",
        );
      }

      bool isPasswordValid = _verifyPassword(
        password,
        storedPassword,
        storedSalt,
      );

      if (!isPasswordValid) {
        return AuthResult(
          success: false,
          errorMessage: "Invalid email or password",
        );
      }

      final verification = data['verification'] as Map<String, dynamic>?;
      final status = verification?['status'] ?? '';

      if (status == 'approved') {
        currentUserId = doc.id;

        Map<String, dynamic> userData = Map.from(data);
        userData.remove('password');
        userData.remove('salt');

        return AuthResult(
          success: true,
          userData: userData,
          userId: doc.id,
          userName: data['name'] as String?,
          userEmail: data['email'] as String?,
        );
      } else if (status == 'pending') {
        return AuthResult(
          success: false,
          errorMessage:
          "Your account is currently under review. Please wait for admin approval.",
        );
      } else if (status == 'rejected') {
        final rejectionReason = verification?['rejectionReason'] ?? '';
        return AuthResult(
          success: false,
          errorMessage:
          "Your registration was rejected${rejectionReason.isNotEmpty ? ': $rejectionReason' : ''}. Please resubmit your documents or contact support.",
        );
      } else {
        return AuthResult(
          success: false,
          errorMessage: "Account status unknown. Please contact support.",
        );
      }
    } catch (e) {
      print("Login error: $e");
      return AuthResult(
          success: false,
          errorMessage: "Login failed: $e"
      );
    }
  }

  /// Reset Password generate new salt
  Future<bool> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    try {
      final query = await _firestore
          .collection('car_owners')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return false;
      }

      final doc = query.docs.first;

      // Generate new salt + hash
      final newSalt = _generateSalt();
      final newHashedPassword = _hashPassword(newPassword, newSalt);

      await doc.reference.update({
        'password': newHashedPassword,
        'salt': base64Encode(newSalt),
        'updated_at': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print("Reset password error: $e");
      return false;
    }
  }

  void logout() {
    currentUserId = null;
  }
}

/// Authentication Result Wrapper
class AuthResult {
  final bool success;
  final Map<String, dynamic>? userData;
  final String? errorMessage;
  final String? userId;
  final String? userName;
  final String? userEmail;

  AuthResult({
    required this.success,
    this.userData,
    this.errorMessage,
    this.userId,
    this.userName,
    this.userEmail,
  });
}