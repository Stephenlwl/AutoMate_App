import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EditVehiclePage extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> vehicle;
  final int vehicleIndex;
  final VoidCallback onVehicleUpdated;

  const EditVehiclePage({
    Key? key,
    required this.userId,
    required this.vehicle,
    required this.vehicleIndex,
    required this.onVehicleUpdated,
  }) : super(key: key);

  @override
  State<EditVehiclePage> createState() => _EditVehiclePageState();
}

class _EditVehiclePageState extends State<EditVehiclePage> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final String _secretKey = "X9f@3LpZ7qW!m2CkT8r#Jd6vNb^Hs4Y0";
  late final encrypt.Key key;
  late final encrypt.Encrypter encrypter;

  String? _error;
  List<Map<String, dynamic>> _vehicles = [];
  bool _isLoading = false;
  bool _isUploadingImage = false;

  File? _vocImage;
  String? _vocImageUrl;
  bool _hasUpdatedVoc = false;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _populateFields();
    key = encrypt.Key.fromUtf8(_secretKey);
    encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  void _populateFields() {
    _plateController.text = widget.vehicle['plateNumber'] ?? '';
    _vinController.text = widget.vehicle['vin'] ?? '';
  }

  Future<void> _updateVehicle() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fill in all required fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get current vehicles
      final doc = await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      if (!doc.exists) {
        _showErrorSnackBar('User data not found');
        return;
      }

      List<dynamic> vehicles = List.from(doc.data()!['vehicles']);

      // Check for duplicate plate number (excluding current vehicle)
      bool duplicateFound = false;
      for (int i = 0; i < vehicles.length; i++) {
        if (i != widget.vehicleIndex &&
            vehicles[i]['plateNumber']?.toString().toUpperCase() ==
                _plateController.text.trim().toUpperCase()) {
          duplicateFound = true;
          break;
        }
      }

      if (duplicateFound) {
        _showErrorSnackBar('A vehicle with this plate number already exists');
        return;
      }

      Map<String, dynamic> updatedVehicle = Map.from(widget.vehicle);

      // Check if any changes were made
      bool hasChanges = false;
      String newPlateNumber = _plateController.text.trim().toUpperCase();
      String newVin = _vinController.text.trim().toUpperCase();

      if (newPlateNumber != (widget.vehicle['plateNumber'] ?? '').toUpperCase()) {
        hasChanges = true;
      }

      if (newVin != (widget.vehicle['vin'] ?? '').toUpperCase()) {
        hasChanges = true;
      }

      if (_hasUpdatedVoc) {
        hasChanges = true;
      }

      if (!hasChanges) {
        _showErrorSnackBar('No changes detected');
        return;
      }

      // Upload new VOC if selected
      Map<String, String>? vocData;
      if (_vocImage != null && _hasUpdatedVoc) {
        vocData = await encryptImage(_vocImage);
      }

      // Update vehicle data
      updatedVehicle.addAll({
        'plateNumber': newPlateNumber,
        'vin': newVin,
        'status': 'pending',
        'updatedAt': Timestamp.now(),
        'previousStatus': widget.vehicle['status'] ?? 'approved',
      });

      if (vocData != null) {
        updatedVehicle.addAll({
          'vocUrl': vocData["encrypted"],
          'vocType': vocData["mimeType"],
          'vocIv': vocData["iv"],
        });
      }

      // remove admin note when updating (will be set by admin after review)
      updatedVehicle.remove('adminNote');

      // Update the specific vehicle in the array
      vehicles[widget.vehicleIndex] = updatedVehicle;

      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .update({'vehicles': vehicles});

      _showSuccessSnackBar('Vehicle updated successfully! Awaiting admin approval.');
      widget.onVehicleUpdated();
      Navigator.pop(context);
    } catch (e) {
      _showErrorSnackBar('Failed to update vehicle: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickVocImage() async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          _showErrorSnackBar('Image size must be less than 5MB');
          return;
        }

        setState(() {
          _vocImage = File(picked.path);
          _hasUpdatedVoc = true;
        });

        _showSuccessSnackBar('VOC document selected successfully');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );
  }

  Future<Map<String, String>> encryptImage(File? file) async {
    if (file == null) {
      throw Exception("No file selected to encrypt.");
    }

    try {
      // Detect MIME type safely
      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = "image/jpeg";
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStatus = widget.vehicle['status'] ?? 'approved';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text(
          'Edit Vehicle',
          style: TextStyle(
            color: secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: secondaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Card
              if (currentStatus == 'pending') _buildStatusCard(),

              // Vehicle Info
              _buildVehicleInfoCard(),

              const SizedBox(height: 24),

              // Editable Fields
              _buildSectionHeader('Editable Information'),
              const SizedBox(height: 16),

              // plate number
              _buildTextField(
                controller: _plateController,
                label: 'Plate Number',
                hint: 'Enter your plate number',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Plate number is required';
                  }
                  if (value.trim().length < 3) {
                    return 'Plate number must be at least 3 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // VIN
              _buildTextField(
                controller: _vinController,
                label: 'VIN / Chassis Number',
                hint: '17-digit VIN (e.g. 1HGCM82633A004352)',
                maxLength: 17,
                validator: (value) {
                  if (value != null &&
                      value.trim().isNotEmpty &&
                      value.trim().length != 17) {
                    return 'VIN must be exactly 17 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // VOC Document Section
              _buildSectionHeader('Vehicle Documentation (VOC)'),
              const SizedBox(height: 16),
              _buildVocUploadSection(),

              const SizedBox(height: 32),

              // Update Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading || _isUploadingImage ? null : _updateVehicle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text('Updating...'),
                    ],
                  )
                      : const Text(
                    'Update Vehicle',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Info text about admin review
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Any changes to your vehicle information will require admin approval before taking effect.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.pending_actions,
            color: Colors.orange.shade600,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Admin Review',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your vehicle updates are currently being reviewed by our admin team.',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVocUploadSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.file_upload, color: primaryColor),
              const SizedBox(width: 8),
              const Text(
                'VOC Document',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_vocImage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('New VOC document selected')),
                  TextButton(
                    onPressed: () => setState(() {
                      _vocImage = null;
                      _hasUpdatedVoc = false;
                    }),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isUploadingImage ? null : _pickVocImage,
              icon: _isUploadingImage
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.camera_alt),
              label: Text(_isUploadingImage
                  ? 'Selecting...'
                  : _vocImage != null
                  ? 'Change VOC Document'
                  : 'Upload New VOC Document'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: primaryColor),
                foregroundColor: primaryColor,
              ),
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Upload a clear photo of your Vehicle Ownership Certificate (VOC). Leave empty to keep current document.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoCard() {
    final make = widget.vehicle['make'] ?? 'Unknown';
    final model = widget.vehicle['model'] ?? 'Unknown';
    final year = widget.vehicle['year']?.toString() ?? '';
    final fuelType = widget.vehicle['fuelType'];
    final displacement = widget.vehicle['displacement'];
    final sizeClass = widget.vehicle['sizeClass'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle Information',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$make $model${year.isNotEmpty ? ' ($year)' : ''}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (fuelType != null)
                _buildInfoChip(Icons.local_gas_station, fuelType),
              if (displacement != null)
                _buildInfoChip(Icons.settings, '${displacement}L'),
              if (sizeClass != null)
                _buildInfoChip(Icons.straighten, sizeClass),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vehicle specifications cannot be changed. Only plate number, VIN, and VOC document can be updated.',
                    style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: secondaryColor,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            filled: true,
            fillColor: cardColor,
          ),
          maxLength: maxLength,
          textCapitalization: TextCapitalization.characters,
          validator: validator,
        ),
      ],
    );
  }
}