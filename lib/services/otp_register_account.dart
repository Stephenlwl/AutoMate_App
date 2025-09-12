import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// In-memory otp store (email to record)
final Map<String, Map<String, dynamic>> otpStore = {};

/// Config
const smtpUsername = 'stephenlwlhotmailcom@gmail.com';
const smtpPassword = 'eiau bqdb wkgj qbfl';
const logoUrl = 'https://yourcdn.com/assets/logo.png';
final smtpServer = gmail(smtpUsername, smtpPassword);

/// Generate and send otp email
Future<void> sendOtpEmailSMTP({required String toEmail}) async {
  final otpCode = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
  final otpCodeHash = sha256.convert(utf8.encode(otpCode)).toString();

  // store otp with expiry
  otpStore[toEmail] = {
    'otpCode': otpCodeHash,
    'expires': DateTime.now().millisecondsSinceEpoch + (60 * 1000), // 1 minute expiry
  };

  final message = Message()
    ..from = Address(smtpUsername, 'AutoMate Verification')
    ..recipients.add(toEmail)
    ..subject = 'Your AutoMate Verification OTP'
    ..html = '''
      <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; max-width: 500px; margin: auto; background: #fafafa;">
        
        <div style="text-align:center; margin-bottom:20px;">
          <img src="$logoUrl" alt="AutoMate Logo" style="max-height:60px;">
        </div>

        <h2 style="color:#FF6B00; text-align:center; margin-bottom:20px;">AutoMate Email Verification</h2>

        <p style="font-size:14px; color:#333; text-align:center;">
          Thank you for registering with <b>AutoMate</b>. <br>
          Please use the following One-Time Password (OTP) to verify your email:
        </p>

        <!-- OTP container -->
        <div style="font-size:28px; font-weight:bold; color:#222; background:#fff; border:1px dashed #FF6B00; padding:15px; text-align:center; margin:20px auto; width:200px; border-radius:6px;">
          $otpCode
        </div>

        <p style="font-size:13px; color:#666; text-align:center;">
          This code will expire in <b>1 minute</b>. <br>
          If you did not request this, please ignore this email.
        </p>

        <hr style="margin:30px 0; border:none; border-top:1px solid #eee;">
        <p style="font-size:12px; color:#999; text-align:center;">
          © ${DateTime.now().year} AutoMate. All rights reserved.
        </p>
      </div>
    ''';

  try {
    await send(message, smtpServer);
    print("OTP sent to $toEmail (code: $otpCode)");
  } on MailerException catch (e) {
    print("Failed to send OTP: $e");
    throw Exception("Failed to send OTP email");
  }
}

/// Verify OTP
bool verifyOtp(String toEmail, String otpInput) {
  final record = otpStore[toEmail];
  if (record == null) {
    print("No OTP found for $toEmail");
    return false;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  if (now > record['expires']) {
    otpStore.remove(toEmail);
    print("OTP expired for $toEmail");
    return false;
  }

  final hash = sha256.convert(utf8.encode(otpInput)).toString();
  if (hash != record['otpCode']) {
    otpStore.remove(toEmail); // prevent reuse
    print("Invalid OTP entered for $toEmail");
    return false;
  }

  otpStore.remove(toEmail); // one-time use
  print("OTP verified successfully for $toEmail");
  return true;
}
