import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../model/service_center_model.dart';
import '../../services/image_decryption_service.dart';

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

class TowingRequestTrackingPage extends StatefulWidget {
  final String requestId;
  final String userId;

  const TowingRequestTrackingPage({
    super.key,
    required this.requestId,
    required this.userId,
  });

  @override
  State<TowingRequestTrackingPage> createState() =>
      _TowingRequestTrackingPageState();
}

class _TowingRequestTrackingPageState extends State<TowingRequestTrackingPage> {

  Map<String, dynamic>? _requestData;
  Map<String, dynamic>? _driverData;
  ServiceCenter? _serviceCenter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRequestData();
    _listenToRequestUpdates();
  }

  Future<void> _loadRequestData() async {
    try {
      final requestDoc = await FirebaseFirestore.instance
          .collection('towing_requests')
          .doc(widget.requestId)
          .get();

      if (requestDoc.exists) {
        setState(() {
          _requestData = requestDoc.data()!;
        });

        // Load driver data if assigned
        if (_requestData!['driverId'] != null) {
          await _loadDriverData(_requestData!['driverId']);
        }

        // Load service center data
        if (_requestData!['serviceCenterId'] != null) {
          await _loadServiceCenterData(_requestData!['serviceCenterId']);
        }
      }
    } catch (e) {
      debugPrint('Error loading request data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDriverData(String driverId) async {
    try {
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();

      if (driverDoc.exists) {
        setState(() {
          _driverData = driverDoc.data()!;
        });
      }
    } catch (e) {
      debugPrint('Error loading driver data: $e');
    }
  }

  Future<void> _loadServiceCenterData(String serviceCenterId) async {
    try {
      final serviceCenterDoc = await FirebaseFirestore.instance
          .collection('service_centers')
          .doc(serviceCenterId)
          .get();

      if (serviceCenterDoc.exists) {
        setState(() {
          _serviceCenter = ServiceCenter.fromFirestore(
              serviceCenterDoc.id,
              serviceCenterDoc.data()!
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading service center data: $e');
    }
  }

  void _listenToRequestUpdates() {
    FirebaseFirestore.instance
        .collection('towing_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _requestData = snapshot.data()!;
        });

        // Load driver data if newly assigned
        if (_requestData!['driverId'] != null && _driverData == null) {
          _loadDriverData(_requestData!['driverId']);
        }

        // Load service center data if not loaded
        if (_requestData!['serviceCenterId'] != null && _serviceCenter == null) {
          _loadServiceCenterData(_requestData!['serviceCenterId']);
        }
      }
    });
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Looking for available driver...';
      case 'accepted':
        return 'Your towing request has been accepted';
      case 'dispatched':
        return 'Driver assigned and on the way';
      case 'ongoing':
        return 'Driver has arrived at your location';
      case 'completed':
        return 'Towing service completed';
      case 'decline':
        return 'Your request has been declined';
      case 'cancelled':
        return 'Request cancelled';
      case 'invoice_generated':
        return 'Invoice has been generated please review before proceed to payment';
      default:
        return 'Status unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningColor;
      case 'accepted':
        return AppColors.primaryColor;
      case 'dispatched':
        return Colors.blue;
      case 'ongoing':
        return AppColors.primaryColor;
      case 'completed':
        return AppColors.successColor;
      case 'decline':
        return AppColors.errorColor;
      case 'cancelled':
        return AppColors.errorColor;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Not yet';
    return DateFormat('dd MMM yyyy, HH:mm').format(timestamp.toDate());
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'RM 0.00';
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  Future<void> _makeCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  Widget _buildStatusTimeline() {
    final timestamps = _requestData?['timestamps'] ?? {};
    final statusHistory = _requestData?['statusHistory'] ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
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
          const Text(
            'Request Timeline',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...statusHistory.map<Widget>((history) => _buildTimelineItem(
            history['status'] ?? '',
            history['timestamp'] ?? Timestamp.now(),
            history['notes'] ?? '',
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String status, Timestamp timestamp, String notes) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusMessage(status),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatAddress(ServiceCenter? address) {
    if (address == null) return 'Unknown location';

    final parts =
    [
      address.addressLine1,
      address.addressLine2!,
      address.city,
      address.state,
      address.postalCode,
    ].where((part) => part.isNotEmpty && part.toString().isNotEmpty).toList();

    return parts.join(', ');
  }

  Widget _buildServiceImage(
      String imageStr, {
        double width = 60,
        double height = 60,
      }) {
    try {
      if (imageStr.startsWith('data:image')) {
        // Handle base64 image
        final base64Str = imageStr.split(',').last;
        final bytes = base64Decode(base64Str);
        return Container(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint("Base64 image error: $error");
                return _buildDefaultImagePlaceholder(width, height);
              },
            ),
          ),
        );
      } else {
        // Handle network image
        return Container(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imageStr,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                        value:
                        loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Image loading error: $error');
                return _buildDefaultImagePlaceholder(width, height);
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Image build error: $e");
      return _buildDefaultImagePlaceholder(width, height);
    }
  }

  Widget _buildDefaultImagePlaceholder(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.business_rounded, size: 24, color: AppColors.textMuted),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryColor),
        ),
      );
    }

    if (_requestData == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          title: const Text('Request Not Found'),
        ),
        body: const Center(
          child: Text('Request information not available'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.cardColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Towing Request Status',
          style: TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getStatusColor(_requestData!['status']),
                    _getStatusColor(_requestData!['status']).withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(_requestData!['status']).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    _requestData!['status'] == 'completed' ? Icons.check_circle :
                    _requestData!['status'] == 'cancelled' ? Icons.cancel :
                    Icons.local_shipping,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getStatusMessage(_requestData!['status']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Request ID: ${widget.requestId.substring(0, 8).toUpperCase()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Driver Information (if assigned)
            if (_driverData != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(12),
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
                    const Text(
                      'Driver Information',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: _buildDriverImage(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverData!['name'] ?? 'Unknown Driver',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_driverData!['rating'] != null)
                                Row(
                                  children: [
                                    Icon(Icons.star, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      _driverData!['rating'].toString(),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        if (_driverData!['phoneNo'] != null)
                          IconButton(
                            onPressed: () => _makeCall(_driverData!['phoneNo']),
                            icon: Container(
                              padding: const EdgeInsets.all(12),
                              child: const Icon(
                                Icons.phone,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildDriverVehicleInfo(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_serviceCenter != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(12),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Service Center Information',
                          style: TextStyle(
                            color: AppColors.secondaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_serviceCenter!.serviceCenterPhoneNo.isNotEmpty)
                          IconButton(
                            onPressed: () => _makeCall(_serviceCenter!.serviceCenterPhoneNo),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              child: const Icon(
                                Icons.phone,
                                color: AppColors.errorColor,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 120,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _serviceCenter!.serviceCenterPhoto.isNotEmpty
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: _buildServiceImage(
                              _serviceCenter!.serviceCenterPhoto,
                              width: 300,
                              height: 100,
                            ),
                          ): Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.business_rounded,
                              size: 32,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _serviceCenter!.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _formatAddress(_serviceCenter!),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Vehicle Information
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(12),
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
                  const Text(
                    'Vehicle Information',
                    style: TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_requestData!['vehicleInfo'] != null) ...[
                    _buildDetailRow('Make', _requestData!['vehicleInfo']['make'] ?? 'N/A'),
                    _buildDetailRow('Model', _requestData!['vehicleInfo']['model'] ?? 'N/A'),
                    _buildDetailRow('Year', _requestData!['vehicleInfo']['year'] ?? 'N/A'),
                    _buildDetailRow('Plate Number', _requestData!['vehicleInfo']['plateNumber'] ?? 'N/A'),
                    _buildDetailRow('Size Class', _requestData!['vehicleInfo']['sizeClass'] ?? 'N/A'),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Pricing & Distance Information
            if (_requestData!['pricingBreakdown'] != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(12),
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
                    const Text(
                      'Pricing Breakdown',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPricingRow('Base Fee', _formatCurrency(_requestData!['pricingBreakdown']['baseFee'])),
                    _buildPricingRow(
                      'Distance Cost',
                      _formatCurrency(_requestData!['pricingBreakdown']['distanceCost']),
                      description: '${_requestData!['pricingBreakdown']['distanceInKm']} km × RM ${_requestData!['pricingBreakdown']['perKmRate']}/km',
                    ),if (_requestData!['pricingBreakdown']['luxurySurcharge'] != null)
                      _buildPricingRow('Luxury Surcharge', _formatCurrency(_requestData!['pricingBreakdown']['luxurySurcharge'])),
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildPricingRow(
                        'Estimated Cost',
                        _formatCurrency(_requestData!['estimatedCost']),
                        isTotal: true
                    ),
                    if (_requestData!['finalCost'] != null)
                      _buildPricingRow(
                          'Final Cost',
                          _formatCurrency(_requestData!['finalCost']),
                          isTotal: true
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Location Information
            if (_requestData!['location'] != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(12),
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
                    const Text(
                      'Location Details',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_requestData!['location']['customer'] != null) ...[
                      const Text(
                        'Pickup Location:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_requestData!['location']['customer']['address'] != null) ...[
                        _buildDetailRow('Address', _requestData!['location']['customer']['address']['full'] ?? 'N/A'),
                        if (_requestData!['location']['customer']['address']['street'] != null)
                          _buildDetailRow('Street', _requestData!['location']['customer']['address']['street']),
                        if (_requestData!['location']['customer']['address']['city'] != null)
                          _buildDetailRow('City', _requestData!['location']['customer']['address']['city']),
                        if (_requestData!['location']['customer']['address']['state'] != null)
                          _buildDetailRow('State', _requestData!['location']['customer']['address']['state']),
                      ],
                    ],
                    if (_requestData!['distance'] != null)
                      _buildDetailRow('Distance to Service Center', '${_requestData!['distance'].toStringAsFixed(1)} km'),
                    if (_requestData!['coverageArea'] != null)
                      _buildDetailRow('Coverage Area', '${_requestData!['coverageArea']} km'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Service Details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(12),
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
                  const Text(
                    'Service Details',
                    style: TextStyle(
                      color: AppColors.secondaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('Towing Type', _requestData!['towingType']),
                  _buildDetailRow('Service Center', _requestData!['serviceCenterName']),
                  if (_requestData!['responseTime'] != null)
                    _buildDetailRow('Response Time', '${_requestData!['responseTime']} minutes'),
                  if (_requestData!['estimatedDuration'] != null)
                    _buildDetailRow('Estimated Duration', '${_requestData!['estimatedDuration']} minutes'),
                  if (_requestData!['description']?.isNotEmpty == true)
                    _buildDetailRow('Description', _requestData!['description']),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Status Timeline
            _buildStatusTimeline(),

            const SizedBox(height: 32),

            // Action buttons based on status
            if (_requestData!['status'] == 'pending') ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => _cancelRequest(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorColor,
                    side: BorderSide(color: AppColors.errorColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel Request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDriverImage() {
    if (_driverData == null) {
      return const Icon(
        Icons.person,
        color: AppColors.primaryColor,
        size: 30,
      );
    }

    final driverImage = _driverData!['driverImage'];

    if (driverImage == null || driverImage.toString().isEmpty) {
      return const Icon(
        Icons.person,
        color: AppColors.primaryColor,
        size: 30,
      );
    }

    try {
      const secretKey = "AUTO_MATE_SECRET_KEY_256";
      final decryptedImage = CryptoJSCompat.decrypt(driverImage.toString(), secretKey);

      if (decryptedImage.isNotEmpty) {
        if (decryptedImage.startsWith('data:')) {
          return _buildBase64Image(decryptedImage);
        }
        else if (decryptedImage.startsWith('http')) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.network(
              decryptedImage,
              fit: BoxFit.cover,
              width: 60,
              height: 60,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Driver network image error: $error');
                return const Icon(
                  Icons.person,
                  color: AppColors.primaryColor,
                  size: 30,
                );
              },
            ),
          );
        } else {
          debugPrint('Driver image is not a valid URL or data URI: ${decryptedImage.substring(0, min(100, decryptedImage.length))}');
        }
      }
    } catch (e) {
      debugPrint('Error decrypting driver image: $e');
      try {
        if (driverImage.toString().startsWith('data:')) {
          return _buildBase64Image(driverImage.toString());
        } else if (driverImage.toString().startsWith('http')) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.network(
              driverImage.toString(),
              fit: BoxFit.cover,
              width: 60,
              height: 60,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.person,
                  color: AppColors.primaryColor,
                  size: 30,
                );
              },
            ),
          );
        }
      } catch (e2) {
        debugPrint('Error displaying driver image without decryption: $e2');
      }
    }

    return const Icon(
      Icons.person,
      color: AppColors.primaryColor,
      size: 30,
    );
  }

  Widget _buildBase64Image(String dataUri) {
    try {
      final base64String = dataUri.split(',').last;

      // Decode base64 to bytes
      final bytes = base64.decode(base64String);

      return ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Base64 image error: $error');
            return const Icon(
              Icons.person,
              color: AppColors.primaryColor,
              size: 30,
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Error processing base64 image: $e');
      return const Icon(
        Icons.person,
        color: AppColors.primaryColor,
        size: 30,
      );
    }
  }

  Widget _buildDriverVehicleInfo() {
    final driverVehicleInfo = _requestData?['driverVehicleInfo'];

    if (driverVehicleInfo == null) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Vehicle Image
          Container(
            width: 120,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildVehicleImage(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Driver Vehicle',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${driverVehicleInfo['carPlate'] ?? 'N/A'} - ${driverVehicleInfo['make'] ?? ''} ${driverVehicleInfo['model'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (driverVehicleInfo['year'] != null)
                  Text(
                    'Year: ${driverVehicleInfo['year']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleImage() {
    final driverVehicleInfo = _requestData?['driverVehicleInfo'];
    final vehicleImages = driverVehicleInfo?['vehicleImage'];

    if (vehicleImages == null ||
        vehicleImages is! List ||
        vehicleImages.isEmpty ||
        vehicleImages[0].toString().isEmpty) {
      return const Icon(
        Icons.directions_car,
        color: AppColors.primaryColor,
        size: 24,
      );
    }

    try {
      const secretKey = "AUTO_MATE_SECRET_KEY_256";
      final encryptedImage = vehicleImages[0].toString();
      final decryptedImage = CryptoJSCompat.decrypt(encryptedImage, secretKey);

      debugPrint('Vehicle image decryption result: ${decryptedImage.isNotEmpty ? "Success" : "Empty"}');
      debugPrint('Vehicle image starts with: ${decryptedImage.substring(0, min(50, decryptedImage.length))}');

      if (decryptedImage.isNotEmpty) {
        // Handle data URI (base64 image)
        if (decryptedImage.startsWith('data:')) {
          return _buildVehicleBase64Image(decryptedImage);
        }
        // Handle regular URL
        else if (decryptedImage.startsWith('http')) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              decryptedImage,
              fit: BoxFit.cover,
              width: 50,
              height: 50,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Vehicle network image error: $error');
                return const Icon(
                  Icons.directions_car,
                  color: AppColors.primaryColor,
                  size: 24,
                );
              },
            ),
          );
        } else {
          debugPrint('Vehicle image is not a valid URL or data URI: ${decryptedImage.substring(0, min(100, decryptedImage.length))}');
        }
      }
    } catch (e) {
      debugPrint('Error decrypting vehicle image: $e');
      try {
        final encryptedImage = vehicleImages[0].toString();
        if (encryptedImage.startsWith('data:')) {
          return _buildVehicleBase64Image(encryptedImage);
        } else if (encryptedImage.startsWith('http')) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              encryptedImage,
              fit: BoxFit.cover,
              width: 50,
              height: 50,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.directions_car,
                  color: AppColors.primaryColor,
                  size: 24,
                );
              },
            ),
          );
        }
      } catch (e2) {
        debugPrint('Error displaying vehicle image without decryption: $e2');
      }
    }

    return const Icon(
      Icons.directions_car,
      color: AppColors.primaryColor,
      size: 24,
    );
  }

  Widget _buildVehicleBase64Image(String dataUri) {
    try {
      debugPrint('Processing vehicle data URI: ${dataUri.substring(0, min(100, dataUri.length))}');
      String base64String;
      if (dataUri.contains(',')) {
        base64String = dataUri.split(',').last;
      } else {
        final base64Index = dataUri.indexOf('base64,');
        if (base64Index != -1) {
          base64String = dataUri.substring(base64Index + 7);
        } else {
          base64String = dataUri;
        }
      }
      base64String = base64String.trim();

      // Decode base64 to bytes
      final bytes = base64.decode(base64String);

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 50,
          height: 50,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Vehicle base64 image display error: $error');
            return const Icon(
              Icons.directions_car,
              color: AppColors.primaryColor,
              size: 24,
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('Error processing vehicle base64 image: $e');
      return const Icon(
        Icons.directions_car,
        color: AppColors.primaryColor,
        size: 24,
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingRow(String label, String value, {bool isTotal = false, String? description}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                  color: isTotal ? AppColors.primaryColor : AppColors.secondaryColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                  color: isTotal ? AppColors.primaryColor : AppColors.secondaryColor,
                ),
              ),
            ],
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  void _cancelRequest() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: const Text('Are you sure you want to cancel this towing request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('towing_requests')
                    .doc(widget.requestId)
                    .update({
                  'status': 'cancelled',
                  'updatedAt': FieldValue.serverTimestamp(),
                  'statusHistory': FieldValue.arrayUnion([{
                    'status': 'cancelled',
                    'timestamp': Timestamp.now(),
                    'updatedBy': 'customer',
                    'notes': 'Request cancelled by customer',
                  }]),
                });
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to cancel request')),
                );
              }
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }
}