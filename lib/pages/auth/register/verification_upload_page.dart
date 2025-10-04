import 'dart:io';
import 'dart:typed_data';
import 'package:automate_application/pages/chat/customer_support_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:automate_application/widgets/progress_bar.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'package:automate_application/services/auth_service.dart';
import 'package:automate_application/services/otp_register_account.dart';
import 'registration_pending_page.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);
}

class VerificationPage extends StatefulWidget {
  final String name, password, brand, model, year, displacement, sizeClass, vin, plateNumber;
  final String? fuelType;

  const VerificationPage({
    super.key,
    required this.name,
    required this.password,
    required this.brand,
    required this.model,
    required this.year,
    required this.fuelType,
    required this.displacement,
    required this.sizeClass,
    required this.vin,
    required this.plateNumber,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _carOwnerNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final TextEditingController _otpController = TextEditingController();
  File? icFile, selfieFile, vocFile;
  Uint8List? icWeb, selfieWeb, vocWeb;
  bool _isSubmitting = false;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF344370);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color successColor = Color(0xFF10B981);
  static const Color errorColor = Color(0xFFE53E3E);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    final cleanValue = value.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanValue.length < 10 || cleanValue.length > 15) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  Future<void> _pickImage(String type) async {
    try {
      final source = await _showImageSourceDialog();
      if (source == null) return;

      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();

        if (bytes.length > 5 * 1024 * 1024) {
          CustomSnackBar.show(
            context: context,
            message:
                'Image size must be less than 6MB. Please choose a smaller image.',
            type: SnackBarType.warning,
          );
          return;
        }

        setState(() {
          final file = File(picked.path);
          if (type == 'ic') icFile = file;
          if (type == 'selfie') selfieFile = file;
          if (type == 'voc') vocFile = file;
        });

        CustomSnackBar.show(
          context: context,
          message: '${_getDocumentName(type)} uploaded successfully!',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      CustomSnackBar.show(
        context: context,
        message: 'Failed to pick image. Please try again.',
        type: SnackBarType.error,
      );
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getDocumentName(String type) {
    switch (type) {
      case 'ic':
        return 'IC Document';
      case 'selfie':
        return 'Selfie with IC';
      case 'voc':
        return 'VOC Document';
      default:
        return 'Document';
    }
  }

  Future<bool> _sendOtp(String email) async {
    try {
      await sendOtpEmailSMTP(toEmail: email);
      return true; // success
    } catch (e) {
      print("Failed to send OTP: $e");
      return false;
    }
  }

  Future<bool> _verifyOtp(String email, String otp) async {
    try {
      final success = verifyOtp(email, otp);
      if (!success) {
        CustomSnackBar.show(
          context: context,
          message: 'Invalid or expired OTP. Please request a new code.',
          type: SnackBarType.error,
        );
      }
      return success;
    } catch (e) {
      print("Failed to verify OTP: $e");
      CustomSnackBar.show(
        context: context,
        message: 'OTP verification failed. Please try again.',
        type: SnackBarType.error,
      );
      return false;
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      CustomSnackBar.show(
        context: context,
        message: 'Please complete all required fields',
        type: SnackBarType.error,
      );
      return;
    }

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final carOwnerName = _carOwnerNameController.text.trim();

    if (icFile == null || selfieFile == null || vocFile == null) {
      CustomSnackBar.show(
        context: context,
        message: 'All documents must be uploaded before submitting.',
        type: SnackBarType.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final sent = await _sendOtp(email);
      if (!sent) throw Exception("Failed to send OTP email");

      final otpValid = await showOtpDialog(
        context: context,
        email: email,
        controller: _otpController,
        onVerify: _verifyOtp,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
      );
      if (!otpValid) {
        CustomSnackBar.show(
          context: context,
          message: 'Email verification failed. Please try again.',
          type: SnackBarType.error,
        );
        return;
      }

      final authService = AuthService();
      final status = await authService.registerCarOwner(
        name: widget.name,
        email: email,
        role: 'car owner',
        phone: phone,
        carOwnerName: carOwnerName,
        password: widget.password,
        make: widget.brand,
        model: widget.model,
        year: widget.year,
        fuelType: widget.fuelType,
        displacement: widget.displacement,
        sizeClass: widget.sizeClass,
        vin: widget.vin,
        plateNumber: widget.plateNumber,
        icImage: icFile,
        selfieImage: selfieFile,
        vocImage: vocFile,
      );

      if (status == 'pending') {
        Navigator.pushReplacementNamed(context, '/register/pending');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Your account is under review. Please wait for admin approval.",
            ),
          ),
        );
        return;
      }

      CustomSnackBar.show(
        context: context,
        message: 'Registration submitted successfully!',
        type: SnackBarType.success,
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RegistrationPendingPage()),
      );
    } catch (e) {
      _showErrorDialog("Registration failed: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> showOtpDialog({
    required BuildContext context,
    required String email,
    required TextEditingController controller,
    required Future<bool> Function(String email, String code) onVerify,
    required Color primaryColor,
    required Color secondaryColor,
  }) async {
    bool isVerifying = false;
    bool otpExpired = false;
    Timer? otpTimer;
    int secondsRemaining = 60;
    String timerText = "01:00";

    void startTimer(StateSetter setState) {
      otpTimer?.cancel();
      secondsRemaining = 60;
      otpExpired = false;
      timerText = "01:00";
      otpTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (secondsRemaining <= 0) {
          timer.cancel();
          setState(() => otpExpired = true);
        } else {
          secondsRemaining--;
          final minutes = (secondsRemaining ~/ 60).toString().padLeft(2, "0");
          final seconds = (secondsRemaining % 60).toString().padLeft(2, "0");
          setState(() => timerText = "$minutes:$seconds");
        }
      });
    }

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => StatefulBuilder(
                builder: (context, setState) {
                  if (otpTimer == null) startTimer(setState);

                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text(
                      "Email Verification",
                      style: TextStyle(fontWeight: FontWeight.bold,
                      color: AppColors.primaryColor),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "We've sent a 6-digit code to:",
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Timer / Expired Status
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                otpExpired
                                    ? Colors.red.shade50
                                    : primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  otpExpired
                                      ? Colors.red.shade300
                                      : primaryColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                otpExpired ? Icons.warning_amber : Icons.timer,
                                color: otpExpired ? Colors.red : primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                otpExpired
                                    ? 'OTP has expired'
                                    : 'Time remaining: $timerText',
                                style: TextStyle(
                                  color: otpExpired ? Colors.red : primaryColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // OTP Input
                        TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            labelText: "Enter 6-digit OTP",
                            border: OutlineInputBorder(),
                            counterText: "",
                            prefixIcon: Icon(Icons.security),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      // Resend Button
                      TextButton(
                        onPressed:
                            isVerifying
                                ? null
                                : () {
                                  setState(() {
                                    controller.clear();
                                    startTimer(setState);
                                  });
                                },
                        child: Text(
                          "Resend OTP",
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                      // Verify Button
                      Row(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: surfaceColor,
                              foregroundColor: primaryColor,
                            ),
                            onPressed:
                            isVerifying
                                ? null
                                : () => Navigator.pop(context, false),
                            child: const Text("Cancel"),
                          ),
                          SizedBox(height: 5),

                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed:
                                (isVerifying || otpExpired)
                                    ? null
                                    : () async {
                                      if (controller.text.length != 6) {
                                        CustomSnackBar.show(
                                          context: context,
                                          message:
                                              'Please enter the full 6-digit code',
                                          type: SnackBarType.warning,
                                        );
                                        return;
                                      }
                                      setState(() => isVerifying = true);
                                      final ok = await onVerify(
                                        email,
                                        controller.text,
                                      );
                                      otpTimer?.cancel();
                                      Navigator.pop(context, ok);
                                    },
                            child:
                                isVerifying
                                    ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Text("Verify"),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
        ) ??
        false;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red.shade700),
                const SizedBox(width: 8),
                const Text("Error"),
              ],
            ),
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

  Widget _buildUploadButton(
    String label,
    String type,
    File? file,
  ) {
    final uploaded = file != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _isSubmitting ? null : () => _pickImage(type),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      uploaded ? Colors.green.shade300 : Colors.grey.shade300,
                  width: uploaded ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
                color: uploaded ? Colors.green.shade50 : Colors.grey.shade50,
              ),
              child: Row(
                children: [
                  Icon(
                    uploaded ? Icons.check_circle : Icons.upload_file,
                    color:
                        uploaded ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      uploaded ? "Document Uploaded" : "Tap to Upload",
                      style: TextStyle(
                        color:
                            uploaded
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (uploaded)
                    Icon(Icons.edit, color: Colors.grey.shade600, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.height < 700;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: screenSize.width * 0.06,
                vertical: isSmallScreen ? 8 : 16,
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(isSmallScreen),
                      SizedBox(height: isSmallScreen ? 20 : 32),
                      _buildFormCard(isSmallScreen),
                      SizedBox(height: isSmallScreen ? 20 : 32),
                      _buildFooter(),
                      SizedBox(height: isSmallScreen ? 20 : 32),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: surfaceColor,
      elevation: 0,
      scrolledUnderElevation: 1,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: secondaryColor,
            size: 16,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        "Step 3 of 3",
        style: TextStyle(
          color: secondaryColor,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    return Column(
      children: [
        // Logo
        Container(
          width: isSmallScreen ? 110 : 130,
          height: isSmallScreen ? 110 : 130,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset(
              'assets/AutoMateLogoWithoutBackground.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.directions_car_rounded,
                  size: isSmallScreen ? 24 : 32,
                  color: primaryColor,
                );
              },
            ),
          ),
        ),

        SizedBox(height: isSmallScreen ? 3 : 6),

        Text(
          'Identity & Vehicle Verification',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 24,
            fontWeight: FontWeight.w700,
            color: secondaryColor,
            letterSpacing: -0.5,
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: isSmallScreen ? 4 : 8),

        Text(
          'Provide details about your car',
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),

        SizedBox(height: isSmallScreen ? 16 : 20),
        StepProgressBar(currentStep: 3),
      ],
    );
  }

  Widget _buildFormCard(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 28),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildInputField(
              controller: _emailController,
              label: 'Email Address',
              hint: '...@gmail.com',
              icon: Icons.email,
              validator: _validateEmail,
            ),

            const SizedBox(height: 20),

            _buildInputField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: '01123456789',
              icon: Icons.phone_android,
              validator: _validatePhone,
            ),

            const SizedBox(height:20),

            _buildInputField(
              controller: _carOwnerNameController,
              label: 'Car Owner Name',
              hint: 'Enter the car owner name',
              icon: Icons.person,
            ),

            const SizedBox(height: 28),
            _buildUploadButton("Identity Card (IC) of the Car Owner", "ic", icFile),
            _buildUploadButton("Your selfie with IC", "selfie", selfieFile),
            _buildUploadButton("Vehicle Ownership Card (VOC)", "voc", vocFile),
            const SizedBox(height: 32),

            // submission button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: surfaceColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSubmitting ? null : _handleSubmit,
                child:
                    _isSubmitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: surfaceColor,
                            strokeWidth: 2,
                          ),
                        )
                        : const Text(
                          "Submit Verification",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    void Function(String)? onFieldSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          validator: validator,
          maxLength: maxLength,
          onFieldSubmitted: onFieldSubmitted,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            prefixIcon: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor, size: 18),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: errorColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            counterText: maxLength != null ? null : '',
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.all(22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: secondaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: secondaryColor.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Terms text
          Text(
            'By submitting, you agree to our Terms of Service and Privacy Policy. '
            'Your documents will be securely encrypted and reviewed by our admin team.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
