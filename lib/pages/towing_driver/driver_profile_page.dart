import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:automate_application/services/auth_service.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color primaryLight = Color(0xFFF3A169);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color secondaryColor = Color(0xFF1E293B);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color(0xFFF1F5F9);
  static const Color accentColor = Color(0xFF06B6D4);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color borderColor = Color(0xFFE2E8F0);
}

class DriverProfilePage extends StatefulWidget {
  final String userId;

  const DriverProfilePage({super.key, required this.userId});

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // User data
  String? _userName;
  String? _userEmail;
  String? _userPhone;
  String? _joinDate;
  String? _verificationStatus;

  bool _loading = true;
  bool _editingPhone = false;
  bool _resettingPassword = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userDoc = await _firestore.collection('drivers').doc(widget.userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;

        setState(() {
          _userName = userData['name'] ?? 'No Name';
          _userEmail = userData['email'] ?? 'No Email';
          _userPhone = userData['phoneNo'] ?? 'No Phone';
          _verificationStatus = userData['status'] ?? 'pending';

          // Format join date from timestamp if available
          final createdTimestamp = userData['createdAt'];
          if (createdTimestamp is Timestamp) {
            _joinDate = _formatDate(createdTimestamp.toDate());
          } else {
            _joinDate = 'Unknown';
          }

          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading driver data: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _updatePhoneNumber() async {
    if (_phoneController.text.isEmpty) {
      _showErrorSnackBar('Please enter a phone number');
      return;
    }

    try {
      await _firestore.collection('drivers').doc(widget.userId).update({
        'phone': _phoneController.text,
        'updated_at': FieldValue.serverTimestamp(),
      });

      setState(() {
        _userPhone = _phoneController.text;
        _editingPhone = false;
      });

      _showSnackBar('Phone number updated successfully');
    } catch (e) {
      print('Error updating phone: $e');
      _showErrorSnackBar('Failed to update phone number');
    }
  }

  Future<void> _resetPassword() async {
    if (_newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showErrorSnackBar('Please fill in all password fields');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showErrorSnackBar('New passwords do not match');
      return;
    }

    if (_newPasswordController.text.length < 8) {
      _showErrorSnackBar('Password must be at least 8 characters');
      return;
    }
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(_newPasswordController.text)) {
      _showErrorSnackBar('Password must contain uppercase, lowercase, and number');
      return;
    }

    setState(() {
      _resettingPassword = true;
    });

    try {
      // Use AuthService to reset password
      final success = await _authService.resetDriverPassword(
        email: _userEmail!,
        newPassword: _newPasswordController.text,
      );

      if (success) {
        _showSnackBar('Password reset successfully');
        _cancelPasswordReset();
      } else {
        _showErrorSnackBar('Failed to reset password. Please try again.');
      }
    } catch (e) {
      print('Error resetting password: $e');
      _showErrorSnackBar('Error resetting password: $e');
    } finally {
      setState(() {
        _resettingPassword = false;
      });
    }
  }

  void _cancelPasswordReset() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    setState(() {
      _resettingPassword = false;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.successColor,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.errorColor,
      ),
    );
  }

  Widget _buildVerificationBadge() {
    Color color;
    String text;

    switch (_verificationStatus) {
      case 'approved':
        color = Colors.green;
        text = 'Verified Driver';
      case 'pending':
        color = Colors.orange;
        text = 'Pending Verification';
      case 'rejected':
        color = Colors.red;
        text = 'Verification Failed';
      default:
        color = Colors.grey;
        text = 'Unknown Status';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildUserInfoSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, AppColors.primaryColor.withOpacity(0.2)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primaryColor,
                    radius: 30,
                    child: Text(
                      _userName?.substring(0, 1).toUpperCase() ?? 'D',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? 'Loading...',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildVerificationBadge(),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _buildInfoRow(
                label: 'Email',
                value: _userEmail ?? 'No email',
                showEdit: false,
              ),

              const Divider(height: 24, color: Colors.black),

              if (!_editingPhone)
                _buildInfoRow(
                  label: 'Phone No',
                  value: _userPhone ?? 'No phone number',
                  showEdit: true,
                  onEdit: () {
                    _phoneController.text = _userPhone ?? '';
                    setState(() {
                      _editingPhone = true;
                    });
                  },
                )
              else
                _buildEditPhoneSection(),

              const Divider(height: 24, color: Colors.black),

              _buildInfoRow(
                label: 'Join Since',
                value: _joinDate ?? 'Unknown',
                showEdit: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool showEdit,
    VoidCallback? onEdit,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
        if (showEdit)
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: onEdit,
            color: AppColors.primaryColor,
          ),
      ],
    );
  }

  Widget _buildEditPhoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Phone Number',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            hintText: 'Enter phone number',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _updatePhoneNumber,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _editingPhone = false;
                  });
                },
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPasswordResetSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, AppColors.accentColor.withOpacity(0.1)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_reset, color: AppColors.accentColor),
                  SizedBox(width: 8),
                  Text(
                    'Password Reset',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (!_resettingPassword)
                _buildPasswordResetButton()
              else
                _buildPasswordResetForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordResetButton() {
    return Column(
      children: [
        const Text(
          'Change your password to keep your account secure',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _resettingPassword = true;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Reset Password',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordResetForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter your new password',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _newPasswordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'New Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.grey.shade600,
                size: 20,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            border: OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.grey.shade600,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            ),
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.successColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child : const Text('Reset Password'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelPasswordReset,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),
        const Text(
          'Note: Password must be at least 6 characters long',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadUserData,
        child: ListView(
          children: [
            _buildUserInfoSection(),
            _buildPasswordResetSection(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}