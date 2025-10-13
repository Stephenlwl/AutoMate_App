import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../model/service_center_model.dart';

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

class ServiceAppointmentTrackingPage extends StatefulWidget {
  final String appointmentId;
  final String userId;

  const ServiceAppointmentTrackingPage({
    super.key,
    required this.appointmentId,
    required this.userId,
  });

  @override
  State<ServiceAppointmentTrackingPage> createState() =>
      _ServiceAppointmentTrackingPageState();
}

class _ServiceAppointmentTrackingPageState
    extends State<ServiceAppointmentTrackingPage> {
  Map<String, dynamic>? _appointmentData;
  ServiceCenter? _serviceCenter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAppointmentData();
    _listenToAppointmentUpdates();
  }

  Future<void> _loadAppointmentData() async {
    try {
      final appointmentDoc =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .doc(widget.appointmentId)
              .get();

      if (appointmentDoc.exists) {
        setState(() {
          _appointmentData = appointmentDoc.data()!;
        });

        // Load service center data
        if (_appointmentData!['serviceCenterId'] != null) {
          await _loadServiceCenterData(_appointmentData!['serviceCenterId']);
        }
      }
    } catch (e) {
      debugPrint('Error loading appointment data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadServiceCenterData(String serviceCenterId) async {
    try {
      final serviceCenterDoc =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(serviceCenterId)
              .get();

      if (serviceCenterDoc.exists) {
        setState(() {
          _serviceCenter = ServiceCenter.fromFirestore(
            serviceCenterDoc.id,
            serviceCenterDoc.data()!,
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading service center data: $e');
    }
  }

  void _listenToAppointmentUpdates() {
    FirebaseFirestore.instance
        .collection('service_bookings')
        .doc(widget.appointmentId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            setState(() {
              _appointmentData = snapshot.data()!;
            });

            // Load service center data if not loaded
            if (_appointmentData!['serviceCenterId'] != null &&
                _serviceCenter == null) {
              _loadServiceCenterData(_appointmentData!['serviceCenterId']);
            }
          }
        });
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Waiting for workshop confirmation';
      case 'assigned':
        return 'A technician and bay has been assigned to you';
      case 'confirmed':
        return 'Appointment confirmed and scheduled';
      case 'in_progress':
        return 'Service in progress';
      case 'ready_to_collect':
        return 'Your vehicle is ready to collect';
      case 'completed':
        return 'Service completed';
      case 'cancelled':
        return 'Appointment cancelled';
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
      case 'approved':
        return AppColors.primaryColor;
      case 'assigned':
        return AppColors.secondaryColor;
      case 'confirmed':
        return Colors.blue;
      case 'in_progress':
        return AppColors.primaryColor;
      case 'completed':
        return AppColors.successColor;
      case 'cancelled':
        return AppColors.errorColor;
      case 'invoice_generated':
        return AppColors.primaryLight;
      case 'ready_to_collect':
        return AppColors.primaryColor;
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
    final createdAt = _appointmentData?['createdAt'] as Timestamp?;
    final statusHistory = _appointmentData?['statusHistory'] ?? [];

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
            'Appointment Timeline',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...statusHistory
              .map<Widget>(
                (history) => _buildTimelineItem(
                  history['status'] ?? '',
                  history['timestamp'] ?? Timestamp.now(),
                  history['notes'] ?? '',
                ),
              )
              .toList(),
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
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
            ]
            .where((part) => part.isNotEmpty && part.toString().isNotEmpty)
            .toList();

    return parts.join(', ');
  }

  Widget _buildServiceImage(
    String imageStr, {
    double width = 60,
    double height = 60,
  }) {
    try {
      if (imageStr.startsWith('data:image')) {
        final base64Str = imageStr.split(',').last;
        final bytes = base64.decode(base64Str);
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

    if (_appointmentData == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(title: const Text('Appointment Not Found')),
        body: const Center(
          child: Text('Appointment information not available'),
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
          'Service Appointment Status',
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
                    _getStatusColor(_appointmentData!['status']),
                    _getStatusColor(
                      _appointmentData!['status'],
                    ).withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(
                      _appointmentData!['status'],
                    ).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    _appointmentData!['status'] == 'completed'
                        ? Icons.check_circle
                        : _appointmentData!['status'] == 'cancelled'
                        ? Icons.cancel
                        : Icons.build,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getStatusMessage(_appointmentData!['status']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Appointment ID: ${widget.appointmentId.substring(0, 8).toUpperCase()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Service Center Information
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
                            onPressed:
                                () => _makeCall(
                                  _serviceCenter!.serviceCenterPhoneNo,
                                ),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              child: const Icon(
                                Icons.phone,
                                color: AppColors.primaryColor,
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
                          child:
                              _serviceCenter!.serviceCenterPhoto.isNotEmpty
                                  ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildServiceImage(
                                      _serviceCenter!.serviceCenterPhoto,
                                      width: 300,
                                      height: 100,
                                    ),
                                  )
                                  : Container(
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
                  if (_appointmentData!['vehicle'] != null) ...[
                    _buildDetailRow(
                      'Make',
                      _appointmentData!['vehicle']['make'] ?? 'N/A',
                    ),
                    _buildDetailRow(
                      'Model',
                      _appointmentData!['vehicle']['model'] ?? 'N/A',
                    ),
                    _buildDetailRow(
                      'Year',
                      _appointmentData!['vehicle']['year'] ?? 'N/A',
                    ),
                    _buildDetailRow(
                      'Plate Number',
                      _appointmentData!['vehicle']['plateNumber'] ?? 'N/A',
                    ),
                    _buildDetailRow(
                      'Size Class',
                      _appointmentData!['vehicle']['sizeClass'] ?? 'N/A',
                    ),
                    _buildDetailRow(
                      'Current Mileage',
                      '${_appointmentData!['currentMileage'] ?? 'N/A'} km',
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

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
                  _buildDetailRow(
                    'Service Type',
                    _appointmentData!['selectionType'] ?? 'Individual',
                  ),
                  _buildDetailRow(
                    'Urgency Level',
                    _appointmentData!['urgencyLevel'] ?? 'Standard',
                  ),
                  if (_appointmentData!['scheduledDate'] != null)
                    _buildDetailRow(
                      'Scheduled Date',
                      _formatTimestamp(_appointmentData!['scheduledDate']),
                    ),
                  if (_appointmentData!['scheduledTime'] != null)
                    _buildDetailRow(
                      'Scheduled Time',
                      _appointmentData!['scheduledTime'],
                    ),
                  if (_appointmentData!['estimatedDuration'] != null)
                    _buildDetailRow(
                      'Estimated Duration',
                      '${_appointmentData!['estimatedDuration']} minutes',
                    ),
                  if (_appointmentData!['additionalNotes']?.isNotEmpty == true)
                    _buildDetailRow(
                      'Additional Notes',
                      _appointmentData!['additionalNotes'],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Services Breakdown
            if (_appointmentData!['services'] != null &&
                    (_appointmentData!['services'] as List).isNotEmpty ||
                (_appointmentData!['packages'] != null &&
                    (_appointmentData!['packages'] as List).isNotEmpty)) ...[
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
                      'Services Requested',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_appointmentData!['services'] != null)
                      ...(_appointmentData!['services'] as List)
                          .map<Widget>((service) => _buildServiceRow(service))
                          .toList(),
                    if (_appointmentData!['packages'] != null)
                      ...(_appointmentData!['packages'] as List)
                          .map<Widget>((pkg) => _buildServiceRow(pkg))
                          .toList(),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (_appointmentData!['subtotalRange'] == '') ...[
                      _buildPricingRow(
                        'Subtotal',
                        _formatCurrency(
                          _appointmentData!['subtotal']?.toDouble() ?? 0.0,
                        ),
                        isTotal: true,
                      ),
                    ] else ...[
                      _buildPricingRow(
                        'Subtotal',
                        _appointmentData!['subtotalRange'],
                        isTotal: true,
                      ),
                    ],
                    if (_appointmentData!['sstRange'] == '') ...[
                      const SizedBox(height: 8),
                      _buildPricingRow(
                        'SST (8%)',
                        _formatCurrency(
                          _appointmentData!['sst']?.toDouble() ?? 0.0,
                        ),
                        isTotal: true,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      _buildPricingRow(
                        'SST (8%)',
                        _appointmentData!['sstRange'],
                        isTotal: true,
                      ),
                    ],
                    if (_appointmentData!['totalEstAmountRange'] == '') ...[
                      const SizedBox(height: 8),
                      _buildPricingRow(
                        'Est. Total Amount',
                        _formatCurrency(
                          _appointmentData!['totalEstAmount']?.toDouble() ??
                              0.0,
                        ),
                        isTotal: true,
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      _buildPricingRow(
                        'Est. Total Amount',
                        _appointmentData!['totalEstAmountRange'],
                        isTotal: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Service Maintenances
            if (_appointmentData!['serviceMaintenances'] != null &&
                (_appointmentData!['serviceMaintenances'] as List)
                    .isNotEmpty) ...[
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
                      'Service Maintenance Schedule',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...(_appointmentData!['serviceMaintenances'] as List)
                        .map<Widget>(
                          (maintenance) => _buildMaintenanceRow(maintenance),
                        )
                        .toList(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Status Timeline
            _buildStatusTimeline(),

            const SizedBox(height: 32),

            // Action buttons based on status
            if (_appointmentData!['status'] == 'pending' ||
                _appointmentData!['status'] == 'approved') ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => _cancelAppointment(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorColor,
                    side: BorderSide(color: AppColors.errorColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel Appointment'),
                ),
              ),
            ],

            if (_appointmentData!['status'] == 'completed') ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _showRatingDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Rate Service'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

  Widget _buildServiceRow(Map<String, dynamic> service) {
    final totalPrice = _calculateTotal(service);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  service['serviceName'] ??
                      service['packageName'] ??
                      'Unknown Service',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ),
              if (totalPrice != null)
                Text(
                  totalPrice,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          if (service['duration'] != null)
            Text(
              'Duration: ${service['duration']} minutes',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          if (service['estimatedDuration'] != null)
            Text(
              'Duration: ${service['estimatedDuration']} minutes',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  String? _calculateTotal(Map<String, dynamic> service) {
    // Calculate minimum total
    double minTotal = 0;
    if (service['partPriceMin'] != null && service['partPriceMin'] > 0) {
      minTotal += service['partPriceMin'].toDouble();
    } else if (service['partPrice'] != null && service['partPrice'] > 0) {
      minTotal += service['partPrice'].toDouble();
    }

    if (service['labourPriceMin'] != null && service['labourPriceMin'] > 0) {
      minTotal += service['labourPriceMin'].toDouble();
    } else if (service['labourPrice'] != null && service['labourPrice'] > 0) {
      minTotal += service['labourPrice'].toDouble();
    }

    // Calculate maximum total
    double maxTotal = 0;
    if (service['partPriceMax'] != null && service['partPriceMax'] > 0) {
      maxTotal += service['partPriceMax'].toDouble();
    } else if (service['partPrice'] != null && service['partPrice'] > 0) {
      maxTotal += service['partPrice'].toDouble();
    }

    if (service['labourPriceMax'] != null && service['labourPriceMax'] > 0) {
      maxTotal += service['labourPriceMax'].toDouble();
    } else if (service['labourPrice'] != null && service['labourPrice'] > 0) {
      maxTotal += service['labourPrice'].toDouble();
    }

    // Return formatted price
    if (minTotal > 0 && maxTotal > 0 && minTotal != maxTotal) {
      return 'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
    } else if (minTotal > 0) {
      return 'RM${minTotal.toStringAsFixed(2)}';
    } else if (maxTotal > 0) {
      return 'RM${maxTotal.toStringAsFixed(2)}';
    }

    return 'RM0.00';
  }

  Widget _buildMaintenanceRow(Map<String, dynamic> maintenance) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatServiceType(maintenance['serviceType'] ?? ''),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryColor,
            ),
          ),
          if (maintenance['nextServiceDate'] != null)
            Text(
              'Next Service: ${maintenance['nextServiceDate']}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          if (maintenance['nextServiceMileage'] != null)
            Text(
              'Next Service Mileage: ${maintenance['nextServiceMileage']} km',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  Widget _buildPricingRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color:
                  isTotal ? AppColors.primaryColor : AppColors.secondaryColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 14 : 12,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color:
                  isTotal ? AppColors.primaryColor : AppColors.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  String _formatServiceType(String serviceType) {
    switch (serviceType) {
      case 'engine_oil':
        return 'Engine Oil Change';
      case 'alignment':
        return 'Wheel Alignment';
      case 'battery':
        return 'Battery Replacement';
      case 'tire_rotation':
        return 'Tire Rotation';
      case 'coolant':
        return 'Coolant Flush';
      case 'gear_oil':
        return 'Gear Oil';
      case 'at_fluid':
        return 'AT Fluid';
      default:
        return serviceType.replaceAll('_', ' ').toTitleCase();
    }
  }

  void _cancelAppointment() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Appointment'),
            content: const Text(
              'Are you sure you want to cancel this service appointment?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder:
                          (context) => const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primaryColor,
                            ),
                          ),
                    );

                    // Close the confirmation dialog
                    Navigator.pop(context);

                    final bookingDoc =
                        await FirebaseFirestore.instance
                            .collection('service_bookings')
                            .doc(widget.appointmentId)
                            .get();

                    if (!bookingDoc.exists) {
                      throw Exception('Booking document not found');
                    }

                    final currentData =
                        bookingDoc.data() as Map<String, dynamic>? ?? {};

                    final bookingUpdate = <String, dynamic>{
                      'status': 'cancelled',
                      'updatedAt': Timestamp.now(),
                      'statusUpdatedBy': 'customer',
                      'cancellation': {
                        'cancelledBy': 'customer',
                        'cancelledAt': Timestamp.now(),
                        'reason': 'Cancelled by customer',
                      },
                    };

                    final newStatusHistory = {
                      'status': 'cancelled',
                      'timestamp': Timestamp.now(),
                      'updatedBy': 'customer',
                      'notes': 'Customer has cancelled the booking',
                    };

                    final existingStatusHistory =
                        currentData['statusHistory'] as List? ?? [];

                    bookingUpdate['statusHistory'] = [
                      ...existingStatusHistory,
                      newStatusHistory,
                    ];

                    final existingTimestamps =
                        currentData['timestamps'] as Map<String, dynamic>? ??
                        {};
                    bookingUpdate['timestamps'] = {
                      ...existingTimestamps,
                      'cancelledAt': FieldValue.serverTimestamp(),
                    };

                    // Update the document
                    await FirebaseFirestore.instance
                        .collection('service_bookings')
                        .doc(widget.appointmentId)
                        .update(bookingUpdate);

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Appointment cancelled successfully'),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to cancel appointment'),
                      ),
                    );
                  }
                },
                child: const Text('Yes, Cancel'),
              ),
            ],
          ),
    );
  }

  void _showRatingDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rate Your Experience'),
            content: const Text('Rating feature coming soon!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}

// Extension for string title case
extension StringExtension on String {
  String toTitleCase() {
    return split(' ')
        .map(
          (str) =>
              str.isNotEmpty
                  ? str[0].toUpperCase() + str.substring(1).toLowerCase()
                  : '',
        )
        .join(' ');
  }
}
