import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

Future<void> sendOtpEmailSMTP({
  required String toEmail,
  required String otpCode,
}) async {
  // SMTP credentials
  const smtpUsername = 'stephenlwlhotmailcom@gmail.com';
  const smtpPassword = 'eiau bqdb wkgj qbfl';
  final smtpServer = gmail(smtpUsername, smtpPassword);

  final message = Message()
    ..from = Address(smtpUsername, 'AutoMate Verification')
    ..recipients.add(toEmail)
    ..subject = 'Your AutoMate Verification OTP'
    ..html = '''
      <div style="font-family: sans-serif; padding: 20px; border: 1px solid #ccc;">
        <h2 style="color: #FF6B00;">AutoMate Verification $otpCode</h2>
        <p>Hello,</p>
        <p>Thank you for registering with AutoMate. Please use the following OTP to verify your email address:</p>
        <div style="font-size: 24px; font-weight: bold; margin: 16px 0; color: #333;">
          $otpCode
        </div>
        <p>This code will expire in 5 minutes. Do not share this code with anyone.</p>
        <p>Regards,<br>AutoMate Team</p>
      </div>
    ''';

  try {
    final sendReport = await send(message, smtpServer);
    print('Message sent: ' + sendReport.toString());
  } on MailerException catch (e) {
    print('Message not sent. $e');
    throw Exception('Failed to send OTP email');
  }
}
