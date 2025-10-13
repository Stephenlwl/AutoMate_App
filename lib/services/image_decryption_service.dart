import 'package:flutter/material.dart';
import 'package:flutter/material.dart' hide Key;
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

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