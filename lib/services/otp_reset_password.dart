import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

/// In-memory OTP store (email to record)
final Map<String, Map<String, dynamic>> otpStore = {};

/// Config
const smtpUsername = 'stephenlwlhotmailcom@gmail.com';
const smtpPassword = 'eiau bqdb wkgj qbfl';
final logoPath = 'assets/AutoMateLogoWithoutBackground.png';
final smtpServer = gmail(smtpUsername, smtpPassword);

/// Generate and send otp email
Future<void> sendOtpEmailSMTP({required String toEmail}) async {
  final otpCode = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
  final otpCodeHash = sha256.convert(utf8.encode(otpCode)).toString();

  // Store OTP with i min expiry
  otpStore[toEmail] = {
    'otpCode': otpCodeHash,
    'expires': DateTime.now().millisecondsSinceEpoch + (60 * 1000), // 1 minute expiry
    'attempts': 0, // Track verification attempts
  };

  final message = Message()
    ..from = Address(smtpUsername, 'AutoMate Verification')
    ..recipients.add(toEmail)
    ..subject = 'Your AutoMate Password Reset OTP'
    ..html = '''
      <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px; max-width: 500px; margin: auto; background: #fafafa;">
        
        <div style="text-align:center; margin-bottom:20px;">
           <img src="cid:logo" alt="AutoMate Logo" style="max-height:60px;">
        </div>
        
        <h2 style="color:#FF6B00; text-align:center; margin-bottom:20px;">AutoMate Password Reset</h2>
        
        <p style="font-size:14px; color:#333; text-align:center;">
          You have requested to reset your password for your <b>AutoMate</b> account. <br>
          Please use the following One-Time Password (OTP) to proceed:
        </p>
        
        <!-- OTP container -->
        <div style="font-size:28px; font-weight:bold; color:#222; background:#fff; border:2px solid #FF6B00; padding:15px; text-align:center; margin:20px auto; width:200px; border-radius:8px; box-shadow: 0 2px 10px rgba(255, 107, 0, 0.1);">
          $otpCode
        </div>
        
        <p style="font-size:13px; color:#666; text-align:center;">
          <strong>This code will expire in exactly 1 minute</strong> <br>
          <strong>You have only ONE attempt to use this code</strong> <br><br>
          If you did not request this password reset, please ignore this email and ensure your account security.
        </p>
        
        <div style="background:#f0f8ff; border-left:4px solid #FF6B00; padding:15px; margin:20px 0; border-radius:4px;">
          <p style="margin:0; font-size:12px; color:#555;">
            <strong>Security Notice:</strong> For your protection, this OTP can only be used once. If it expires or fails, you'll need to request a new one.
          </p>
        </div>
        
        <hr style="margin:30px 0; border:none; border-top:1px solid #eee;">
        <p style="font-size:12px; color:#999; text-align:center;">
          © ${DateTime.now().year} AutoMate. All rights reserved.<br>
          This is an automated message, please do not reply.
        </p>
      </div>
    '''
    ..attachments = [
      FileAttachment(File(logoPath))
        ..cid = '<logo>' //match with "cid:logo" in <img>
    ];

  try {
    await send(message, smtpServer);
    print("Password reset OTP sent to $toEmail (code: $otpCode)");
  } on MailerException catch (e) {
    print("Failed to send OTP: $e");
    // Remove the stored OTP if email sending fails
    otpStore.remove(toEmail);
    throw Exception("Failed to send OTP email: ${e.message}");
  }
}

/// Verify OTP with strict one time use and expiry check
bool verifyOtp(String toEmail, String otpInput) {
  final record = otpStore[toEmail];
  if (record == null) {
    print("No OTP found for $toEmail");
    return false;
  }

  final now = DateTime.now().millisecondsSinceEpoch;

  // Check if otp has expired
  if (now > record['expires']) {
    otpStore.remove(toEmail);
    print("OTP expired for $toEmail");
    return false;
  }

  // Increment attempt counter
  record['attempts'] = (record['attempts'] ?? 0) + 1;

  // Check if this is not the first attempt
  if (record['attempts'] > 1) {
    otpStore.remove(toEmail);
    print("Multiple attempts detected for $toEmail - OTP invalidated");
    return false;
  }

  // Verify the OTP code
  final hash = sha256.convert(utf8.encode(otpInput)).toString();
  if (hash != record['otpCode']) {
    otpStore.remove(toEmail); // Remove immediately on wrong code
    print("Invalid OTP entered for $toEmail");
    return false;
  }

  otpStore.remove(toEmail);
  print("OTP verified successfully for $toEmail");
  return true;
}

/// Check if an OTP exists and is still valid for an email
bool isOtpValid(String toEmail) {
  final record = otpStore[toEmail];
  if (record == null) return false;

  final now = DateTime.now().millisecondsSinceEpoch;
  return now <= record['expires'];
}

/// Get remaining time for OTP in seconds
int getOtpRemainingTime(String toEmail) {
  final record = otpStore[toEmail];
  if (record == null) return 0;

  final now = DateTime.now().millisecondsSinceEpoch;
  final remaining = ((record['expires'] - now) / 1000).round();
  return remaining > 0 ? remaining : 0;
}

/// Clear expired otp
void clearExpiredOtps() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final expiredEmails = <String>[];

  otpStore.forEach((email, record) {
    if (now > record['expires']) {
      expiredEmails.add(email);
    }
  });

  for (final email in expiredEmails) {
    otpStore.remove(email);
    print("Cleared expired OTP for $email");
  }
}

/// Cancel OTP for a specific email
void cancelOtp(String toEmail) {
  if (otpStore.containsKey(toEmail)) {
    otpStore.remove(toEmail);
    print("OTP cancelled for $toEmail");
  }
}