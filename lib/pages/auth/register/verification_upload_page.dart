import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:automate_application/widgets/progress_bar.dart';
import 'package:automate_application/services/otp_sender_service.dart';
import 'package:automate_application/services/auth_service.dart';
import 'registration_pending_page.dart';

class VerificationPage extends StatefulWidget {
  final String name, password, brand, model, year, vin, plateNumber;

  const VerificationPage({
    super.key,
    required this.name,
    required this.password,
    required this.brand,
    required this.model,
    required this.year,
    required this.vin,
    required this.plateNumber,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  File? icFile, selfieFile, vocFile;
  Uint8List? icWeb, selfieWeb, vocWeb;
  bool _isSubmitting = false;
  late String _otpCode;

  final _picker = ImagePicker();

  static const orange = Color(0xFFFF6B00);

  Future<void> _pickImage(String type) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        if (kIsWeb) {
          if (type == 'ic') icWeb = bytes;
          if (type == 'selfie') selfieWeb = bytes;
          if (type == 'voc') vocWeb = bytes;
        } else {
          final file = File(picked.path);
          if (type == 'ic') icFile = file;
          if (type == 'selfie') selfieFile = file;
          if (type == 'voc') vocFile = file;
        }
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Error"),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final ic = kIsWeb ? icWeb : icFile;
    final selfie = kIsWeb ? selfieWeb : selfieFile;
    final voc = kIsWeb ? vocWeb : vocFile;

    if (ic == null || selfie == null || voc == null) {
      _showErrorDialog("All documents must be uploaded.");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Generate OTP
      _otpCode = (Random().nextInt(900000) + 100000).toString();
      await sendOtpViaEmail(email, _otpCode);

      final otpValid = await _showOtpDialog();
      if (!otpValid) {
        _showErrorDialog("Incorrect OTP entered.");
        return;
      }

      final carOwnerService = CarOwnerService();
      await carOwnerService.registerCarOwner(
        name: widget.name,
        email: email,
        phone: '',
        password: widget.password,
        brand: widget.brand,
        model: widget.model,
        year: widget.year,
        vin: widget.vin,
        plateNumber: widget.plateNumber,
        icImage: ic,
        selfieImage: selfie,
        vocImage: voc,
        isWeb: kIsWeb,
      );


      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RegistrationPendingPage()),
      );
    } catch (e) {
      _showErrorDialog("Something went wrong: ${e.toString()}");
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  Future<void> sendOtpViaEmail(String email, String otp) async {
    await sendOtpEmailSMTP(toEmail: email, otpCode: otp);
  }

  Future<bool> _showOtpDialog() async {
    final controller = TextEditingController();
    return await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text("Enter OTP sent to your email"),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "6-digit OTP",
                    border: OutlineInputBorder(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                  ElevatedButton(
                    onPressed:
                        () =>
                            Navigator.pop(context, controller.text == _otpCode),
                    child: const Text("Verify"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Widget _buildUploadButton(
    String label,
    String type,
    File? file,
    Uint8List? webData,
  ) {
    final uploaded = file != null || webData != null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, color: Colors.black87),
                label: Text(
                  uploaded ? "Uploaded" : "Choose File",
                  style: TextStyle(
                    color: uploaded ? Colors.green[700] : Colors.black87,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  side: const BorderSide(color: Colors.grey),
                  alignment: Alignment.centerLeft,
                  backgroundColor:
                      uploaded ? Colors.green[50] : Colors.grey[100],
                ),
                onPressed: () => _pickImage(type),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Step 3: Verification")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'assets/AutoMateLogoWithoutBackground.png',
                        height: 100,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Create Your AutoMate Account',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: orange,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text("Let's get you started in 3 steps"),
                      const SizedBox(height: 12),
                      StepProgressBar(currentStep: 3),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email Address",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Please enter your email';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Upload Required Documents",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                _buildUploadButton("Upload IC", "ic", icFile, icWeb),
                const SizedBox(height: 12),
                _buildUploadButton(
                  "Upload Selfie with IC",
                  "selfie",
                  selfieFile,
                  selfieWeb,
                ),
                const SizedBox(height: 12),
                _buildUploadButton(
                  "Upload VOC (Vehicle Ownership Card)",
                  "voc",
                  vocFile,
                  vocWeb,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child:
                        _isSubmitting
                            ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                            : const Text("Submit Verification"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
