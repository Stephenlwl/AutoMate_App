import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../towing_driver/driver_towing_invoice_create_page.dart';
import '../towing_driver/driver_towing_receipt_create_page.dart';

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

class DriverRequestDetailsPage extends StatefulWidget {
  final String? userId;
  final Map<String, dynamic> request;
  final Map<String, dynamic>? userData;

  const DriverRequestDetailsPage({
    super.key,
    this.userId,
    required this.request,
    this.userData,
  });

  @override
  State<DriverRequestDetailsPage> createState() =>
      _DriverRequestDetailsPageState();
}

class _DriverRequestDetailsPageState extends State<DriverRequestDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _customerName;
  bool _isLoading = false;
  String? _invoiceId;
  bool _invoiceLoading = false;

  @override
  initState() {
    super.initState();
    _loadCustomerData();
    _loadRequestData();
    _loadInvoiceId();
  }

  Future<void> _loadCustomerData() async {
    try {
      setState(() => _isLoading = true);

      if (widget.request['userId'] == null) {
        debugPrint('userId is null in request');
        setState(() {
          _customerName = null;
          _isLoading = false;
        });
        return;
      }

      final querySnapshot = await _firestore
          .collection('car_owners')
          .where('id', isEqualTo: widget.request['userId'])
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final customerData = doc.data();
        final customerName = customerData['name'];

        setState(() {
          _customerName = customerName;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading customer data: $e');
      setState(() {
        _customerName = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRequestData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _isLoading = false);
  }

  Future<void> _loadInvoiceId() async {
    try {
      setState(() => _invoiceLoading = true);

      if (widget.request['id'] != null) {
        debugPrint('Loading invoice for request: ${widget.request['id']}');

        final invoiceQuery = await _firestore
            .collection('invoices')
            .where('towingRequestId', isEqualTo: widget.request['id'])
            .limit(1)
            .get();

        if (invoiceQuery.docs.isNotEmpty) {
          final invoiceDoc = invoiceQuery.docs.first;
          debugPrint('Found invoice: ${invoiceDoc.id}');
          setState(() {
            _invoiceId = invoiceDoc.id;
            _invoiceLoading = false;
          });
          return;
        }

        if (widget.request['invoiceId'] != null) {
          debugPrint('Found invoiceId in request: ${widget.request['invoiceId']}');
          setState(() {
            _invoiceId = widget.request['invoiceId'];
            _invoiceLoading = false;
          });
          return;
        }

        debugPrint('No invoice found for request: ${widget.request['id']}');
      }
    } catch (e) {
      debugPrint('Error loading invoice ID: $e');
    } finally {
      setState(() => _invoiceLoading = false);
    }
  }

  Future<void> _updateRequestStatus(
      String requestId,
      String newStatus,
      String notes,
      ) async {
    try {
      final timestamp = Timestamp.now();
      final statusUpdate = {
        'status': newStatus,
        'updatedAt': timestamp,
        'statusUpdatedBy': widget.userData?['name'] ?? 'Driver',
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'timestamp': timestamp,
            'updatedBy': widget.userData?['name'] ?? 'Driver',
            'notes': notes,
          },
        ]),
      };

      final timestamps = {};
      switch (newStatus) {
        case 'ongoing':
          timestamps['serviceStartedAt'] = timestamp;
          break;
        case 'completed':
          timestamps['completedAt'] = timestamp;
          break;
      }

      await _firestore.collection('towing_requests').doc(requestId).update({
        ...statusUpdate,
        ...timestamps,
      });

      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Status updated to ${_getStatusText(newStatus)}',
          type: SnackBarType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to update status',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Cannot make call',
          type: SnackBarType.error,
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningColor;
      case 'accepted':
        return AppColors.primaryColor;
      case 'dispatched':
        return AppColors.accentColor;
      case 'ongoing':
        return AppColors.primaryDark;
      case 'completed':
        return AppColors.successColor;
      case 'cancelled':
        return AppColors.errorColor;
      default:
        return AppColors.textMuted;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'dispatched':
        return 'Dispatched';
      case 'ongoing':
        return 'Ongoing';
      case 'invoice_generated':
        return 'Ready for Receipt';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toDate());
  }

  Widget _buildCustomerCard() {
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
          Row(
            children: [
              Icon(Icons.person, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Text(
                'Customer Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (widget.request['contactNumber'] != null)
                const SizedBox(width: 15),
              IconButton(
                onPressed:
                    () => _callCustomer(widget.request['contactNumber']),
                icon: const Icon(
                  Icons.phone,
                  size: 18,
                  color: AppColors.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.request['contactNumber'] != null)
            _buildDetailRow('Contact Number', widget.request['contactNumber']),
          if (widget.request['email'] != null)
            _buildDetailRow('Email', widget.request['email']),
          if (_customerName != null)
            _buildDetailRow('Customer Name', _customerName!),
        ],
      ),
    );
  }

  Widget _buildVehicleCard() {
    final vehicleInfo =
        widget.request['vehicleInfo'] as Map<String, dynamic>? ?? {};
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
          Row(
            children: [
              Icon(Icons.directions_car_filled, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Text(
                'Vehicle Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Make', vehicleInfo['make'] ?? 'N/A'),
          _buildDetailRow('Model', vehicleInfo['model'] ?? 'N/A'),
          _buildDetailRow('Year', vehicleInfo['year']?.toString() ?? 'N/A'),
          _buildDetailRow('Plate Number', vehicleInfo['plateNumber'] ?? 'N/A'),
          _buildDetailRow('Size Class', vehicleInfo['sizeClass'] ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildServiceDetailsCard() {
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
          Row(
            children: [
              Icon(Icons.miscellaneous_services, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Text(
                'Service Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailRow('Towing Type', widget.request['towingType'] ?? 'N/A'),
          _buildDetailRow(
            'Service Center',
            widget.request['serviceCenterName'] ?? 'N/A',
          ),
          if (widget.request['description'] != null)
            _buildDetailRow('Description', widget.request['description']),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final location = widget.request['location'] as Map<String, dynamic>? ?? {};
    final customerLocation =
        location['customer'] as Map<String, dynamic>? ?? {};

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
          Row(
            children: [
              Icon(Icons.location_on, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Text(
                'Pickup Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (customerLocation['address'] != null)
            _buildDetailRow(
              'Address',
              customerLocation['address']['full'] ?? 'N/A',
            ),
          if (widget.request['distance'] != null)
            _buildDetailRow(
              'Distance',
              '${widget.request['distance'].toStringAsFixed(1)} km',
            ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    final pricing =
        widget.request['pricingBreakdown'] as Map<String, dynamic>? ?? {};
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
          Text(
            'Pricing Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _buildPricingDetailRow(
            'Base Fee',
            'RM ${pricing['baseFee']?.toStringAsFixed(2) ?? '0.00'}',
          ),
          _buildPricingDetailRow(
            'Distance Cost',
            'RM ${pricing['distanceCost']?.toStringAsFixed(2) ?? '0.00'}',
          ),
          if (pricing['luxurySurcharge'] != null)
            _buildPricingDetailRow(
              'Luxury Surcharge',
              'RM ${pricing['luxurySurcharge']?.toStringAsFixed(2)}',
            ),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 8),
          _buildPricingDetailRow(
            'Total Estimated Cost',
            'RM ${widget.request['estimatedCost']?.toStringAsFixed(2) ?? '0.00'}',
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final statusHistory = widget.request['statusHistory'] ?? [];
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
          Text(
            'Request Timeline',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (statusHistory.isNotEmpty)
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
      padding: const EdgeInsets.only(bottom: 12),
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
                  _getStatusText(status),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _formatDate(timestamp),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? AppColors.primaryColor : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                color: isTotal ? AppColors.primaryColor : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingDetailRow(
      String label,
      String value, {
        bool isTotal = false,
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 15 : 14,
              fontWeight: isTotal ? FontWeight.w500 : FontWeight.w400,
              color: isTotal ? AppColors.primaryColor : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 15 : 14,
              fontWeight: isTotal ? FontWeight.w500 : FontWeight.w400,
              color: isTotal ? AppColors.primaryColor : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToReceiptPage() {
    if (_invoiceId == null) {
      CustomSnackBar.show(
        context: context,
        message: 'Invoice not found. Please generate invoice first.',
        type: SnackBarType.error,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TowingReceiptCreatePage(
          invoiceId: _invoiceId!,
          userData: widget.userData ?? {},
          customerName: _customerName ?? 'Customer',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.request['status'] as String? ?? 'unknown';
    final isDispatched = status == 'dispatched';
    final isOngoing = status == 'ongoing';
    final invoiceGenerated = status == 'invoice_generated';

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Request Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.primaryColor,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading request details...',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getStatusColor(status).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getStatusText(status).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(
                      widget.request['createdAt'] as Timestamp?,
                    ),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildCustomerCard(),
            const SizedBox(height: 16),
            _buildVehicleCard(),
            const SizedBox(height: 16),
            _buildServiceDetailsCard(),
            const SizedBox(height: 16),
            if (widget.request['location'] != null) _buildLocationCard(),
            if (widget.request['location'] != null)
              const SizedBox(height: 16),
            if (widget.request['pricingBreakdown'] != null)
              _buildPricingCard(),
            if (widget.request['pricingBreakdown'] != null)
              const SizedBox(height: 16),
            _buildStatusTimeline(),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardColor,
          border: Border(top: BorderSide(color: AppColors.borderColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (widget.request['contactNumber'] != null &&
                    widget.request['status'] != 'completed')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _callCustomer(widget.request['contactNumber']),
                      icon: const Icon(Icons.phone, size: 18),
                      label: const Text('Call Customer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                if (widget.request['contactNumber'] != null &&
                    (isDispatched || isOngoing || invoiceGenerated))
                  const SizedBox(width: 12),

                if (isDispatched)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateRequestStatus(
                        widget.request['id'],
                        'ongoing',
                        'Driver arrived at location and service started',
                      ),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warningColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                if (isDispatched && isOngoing) const SizedBox(width: 12),

                if (isOngoing)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => TowingInvoiceCreatePage(
                              towingRequestId: widget.request['id'],
                              userData: widget.userData ?? {},
                              customerName: _customerName!,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Generate Invoice'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                if (invoiceGenerated)
                  Expanded(
                    child: _invoiceLoading
                        ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primaryColor,
                        ),
                      ),
                    )
                        : ElevatedButton.icon(
                      onPressed: _navigateToReceiptPage,
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('Generate Receipt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _invoiceId != null
                            ? AppColors.successColor
                            : AppColors.textMuted,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),

            if (invoiceGenerated && _invoiceId == null && !_invoiceLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Invoice not found. Please check if invoice was generated.',
                  style: TextStyle(
                    color: AppColors.errorColor,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}