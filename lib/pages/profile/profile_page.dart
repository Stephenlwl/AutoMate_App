import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

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

class CarOwnerProfilePage extends StatefulWidget {
  final String userId;

  const CarOwnerProfilePage({super.key, required this.userId});

  @override
  State<CarOwnerProfilePage> createState() => _CarOwnerProfilePageState();
}

class _CarOwnerProfilePageState extends State<CarOwnerProfilePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // User data
  String? _userName;
  String? _userEmail;
  String? _userPhone;
  String? _joinDate;
  String? _verificationStatus;

  // Vehicles data
  List<Map<String, dynamic>> _vehicles = [];

  bool _loading = true;
  bool _editingPhone = false;
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userDoc =
          await _firestore.collection('car_owners').doc(widget.userId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;

        setState(() {
          _userName = userData['name'] ?? 'No Name';
          _userEmail = userData['email'] ?? 'No Email';
          _userPhone = userData['phone'] ?? 'No Phone';
          _verificationStatus =
              userData['verification']?['status'] ?? 'pending';

          // Format join date from timestamp if available
          final createdTimestamp = userData['created_at'];
          if (createdTimestamp is Timestamp) {
            _joinDate = _formatDate(createdTimestamp.toDate());
          } else {
            _joinDate = 'Unknown';
          }

          // Load vehicles
          final vehiclesData = userData['vehicles'] as List<dynamic>?;
          if (vehiclesData != null) {
            _vehicles =
                vehiclesData.map((vehicle) {
                  final vehicleMap = vehicle as Map<String, dynamic>;
                  return {
                    'make': vehicleMap['make'] ?? '',
                    'model': vehicleMap['model'] ?? '',
                    'year': vehicleMap['year']?.toString() ?? '',
                    'plateNumber': vehicleMap['plateNumber'] ?? '',
                    'status': vehicleMap['status'] ?? 'pending',
                    'isDefault': vehicleMap['isDefault'] ?? false,
                    'fuelType': vehicleMap['fuelType'] ?? '',
                    'displacement': vehicleMap['displacement'] ?? '',
                    'sizeClass': vehicleMap['sizeClass'] ?? '',
                  };
                }).toList();
          }

          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _updatePhoneNumber() async {
    if (_phoneController.text.isEmpty) {
      _showSnackBar('Please enter a phone number');
      return;
    }

    try {
      await _firestore.collection('car_owners').doc(widget.userId).update({
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
      _showSnackBar('Failed to update phone number');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _buildVerificationBadge() {
    Color color;
    String text;

    switch (_verificationStatus) {
      case 'approved':
        color = Colors.green;
        text = 'Verified';
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
                      _userName?.substring(0, 1).toUpperCase() ?? 'U',
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
                label: 'Member Since',
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

  Widget _buildVehiclesSection() {
    if (_vehicles.isEmpty) {
      return Card(
        elevation: 2,
        margin: const EdgeInsets.all(16),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'No vehicles registered',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, AppColors.primaryColor.withOpacity(0.03)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Vehicles',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ..._vehicles.map((vehicle) => _buildVehicleCard(vehicle)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle) {
    final status = vehicle['status'] ?? 'pending';
    final isDefault = vehicle['isDefault'] ?? false;

    Color statusColor;
    String statusText;

    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusText = 'APPROVED';
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'PENDING';
      default:
        statusColor = Colors.grey;
        statusText = status.toUpperCase();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${vehicle['make']} ${vehicle['model']} (${vehicle['year']})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            'Plate: ${vehicle['plateNumber']}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),

          if (vehicle['fuelType'] != null && vehicle['fuelType'].isNotEmpty)
            Text(
              'Fuel: ${vehicle['fuelType']}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),

          if (vehicle['displacement'] != null &&
              vehicle['displacement'].isNotEmpty)
            Text(
              'Displacement: ${vehicle['displacement']}L',
              style: const TextStyle(color: AppColors.textSecondary),
            ),

          const SizedBox(height: 8),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _loadUserData,
                child: ListView(
                  children: [_buildUserInfoSection(), _buildVehiclesSection()],
                ),
              ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}
