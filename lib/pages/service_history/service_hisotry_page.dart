import 'dart:convert';
import 'package:automate_application/pages/service_history/service_receipt_page.dart';
import 'package:automate_application/pages/services/service_appointment_tracking_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:automate_application/pages/service_history/service_invoice_page.dart';
import 'package:automate_application/pages/service_history/towing_invoice_page.dart';
import 'package:automate_application/pages/service_history/towing_receipt_page.dart';
import 'package:url_launcher/url_launcher.dart';
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

class ServiceHistoryPage extends StatefulWidget {
  final String userId, userName, userEmail;

  const ServiceHistoryPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<ServiceHistoryPage> createState() => _ServiceHistoryPageState();
}

class _ServiceHistoryPageState extends State<ServiceHistoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _serviceHistory = [];
  String? _error;

  String _selectedServiceType = 'all';
  String _selectedVehicle = 'all';
  String _selectedTimeFilter = 'all';

  // Vehicle list for filtering
  List<String> _userVehicles = [];
  Map<String, Map<String, dynamic>> _vehicleDetails = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadUserVehicles();
    _loadServiceHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserVehicles() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        final vehicles = data['vehicles'] as List? ?? [];

        setState(() {
          _userVehicles = ['all'];
          _vehicleDetails = {};

          for (var vehicle in vehicles) {
            final plate = vehicle['plateNumber']?.toString() ?? 'Unknown';
            _userVehicles.add(plate);
            _vehicleDetails[plate] = {
              'make': vehicle['make'],
              'model': vehicle['model'],
              'year': vehicle['year'],
              'fuelType': vehicle['fuelType'],
              'sizeClass': vehicle['sizeClass'],
            };
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading user vehicles: $e');
    }
  }

  Future<void> _loadServiceHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      List<Map<String, dynamic>> history = [];

      // Service Bookings
      final bookingsSnapshot =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .where('userId', isEqualTo: widget.userId)
              .orderBy('createdAt', descending: true)
              .get();

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final vehicle = data['vehicle'] as Map<String, dynamic>? ?? {};

        final paymentData = data['payment'] as Map<String, dynamic>?;
        final paidAmount = paymentData?['total'] ?? 0.0;
        final paymentStatus =
            paymentData?['paymentStatus'] ?? paymentData?['status'] ?? 'unpaid';
        final paymentMethod = paymentData?['method'];

        final hasPayment =
            paymentData != null &&
            (paymentData['total'] != null || paymentData['paidAmount'] != null);

        history.add({
          'id': doc.id,
          'type': 'service',
          'serviceCenterId': data['serviceCenterId'],
          'serviceCenterName': await _getServiceCenterName(
            data['serviceCenterId'],
          ),
          'invoiceId': data['invoiceId'],
          'receiptId': data['receiptId'],
          'estimatedDuration': data['estimatedDuration'],
          'status': data['status'] ?? 'unknown',
          'scheduledDate': data['scheduledDate'] as Timestamp?,
          'scheduledTime': data['scheduledTime'],
          'totalEstAmount': data['totalEstAmount'],
          'totalEstAmountRange': data['totalEstAmountRange'],
          'totalAmount': _calculateTotalAmount(data),
          'displayPrice': _getDisplayPrice(data),
          'services': data['services'] ?? [],
          'subtotal': data['subtotal'],
          'subtotalRange': data['subtotalRange'],
          'sst': data['sst'],
          'sstRange': data['sstRange'],
          'totalFixedPrice': data['totalFixedPrice'],
          'totalRangePriceMin': data['totalRangePriceMin'],
          'totalRangePriceMax': data['totalRangePriceMax'],
          'currentMileage': data['currentMileage'],
          'mileageRecordedAt': data['mileageRecordedAt'],
          'serviceMaintenances': data['serviceMaintenances'] ?? [],
          'vehicleId': data['vehicleId'],
          'timestamps': data['timestamps'] ?? {},
          'statusHistory': data['statusHistory'] ?? [],
          'packages': _getAllPackages(data),
          'selectionType': data['selectionType'] ?? 'service',
          'vehicle': vehicle,
          'vehiclePlate': vehicle['plateNumber'] ?? 'Unknown',
          'urgencyLevel': data['urgencyLevel'] ?? 'normal',
          'notes': data['additionalNotes'] ?? 'No notes',
          'contactNumber': await _getServiceCenterContactNumber(
            data['serviceCenterId'],
          ),
          'createdAt': data['createdAt'] as Timestamp?,
          'updatedAt': data['updatedAt'] as Timestamp?,
          'paymentStatus': paymentStatus,
          'paymentMethod': paymentMethod,
          'paidAmount': paidAmount,
          'hasPayment': hasPayment,
          'cancellation': data['cancellation'],
          'rating': data['rating'],
          'technician': data['technicianId'],
          'bay': data['bayId'],
        });
      }

      // Towing Requests
      final towingSnapshot =
          await FirebaseFirestore.instance
              .collection('towing_requests')
              .where('userId', isEqualTo: widget.userId)
              .orderBy('createdAt', descending: true)
              .get();

      for (var doc in towingSnapshot.docs) {
        final data = doc.data();

        final vehicleInfo = _safeMapConversion(data['vehicleInfo']);
        final location = _safeMapConversion(data['location']);
        final pricingBreakdown = _safeMapConversion(data['pricingBreakdown']);
        final payment = _safeMapConversion(data['payment']);
        final rating = _safeMapConversion(data['rating']);
        final timestamps = _safeMapConversion(data['timestamps']);

        // Get location information
        String pickupAddress = 'Location not specified';
        if (location['customer'] != null) {
          final customerLocation = _safeMapConversion(location['customer']);
          final address = _safeMapConversion(customerLocation['address']);
          pickupAddress =
              address['full'] ??
              address['formatted'] ??
              'Location not specified';
        } else if (location['serviceCenter'] != null) {
          // Alternative location structure
          final serviceCenterLocation = _safeMapConversion(
            location['serviceCenter'],
          );
          if (serviceCenterLocation['latitude'] != null &&
              serviceCenterLocation['longitude'] != null) {
            pickupAddress = 'Service Center Location';
          }
        }

        // Payment information
        final paymentStatus = payment['status'] ?? 'unpaid';
        final paymentMethod = payment['method'] ?? 'N/A';
        final paidAmount = payment['paidAmount'] ?? payment['total'] ?? 0.0;
        final hasPayment =
            payment.isNotEmpty && (paidAmount > 0 || paymentStatus == 'paid');

        final serviceCenterContact = _safeMapConversion(
          data['serviceCenterContact'],
        );
        final serviceCenterAddress =
            serviceCenterContact['address'] is String
                ? serviceCenterContact['address']
                : 'Address not available';

        final driverInfo = _safeMapConversion(data['driverInfo']);
        final driverContactNumber = driverInfo['contactNumber'] ?? 'N/A';

        history.add({
          'id': doc.id,
          'type': 'towing',
          'status': data['status'] ?? 'unknown',
          'invoiceId': data['invoiceId'],
          'receiptId': data['receiptId'],
          'serviceCenterId': data['serviceCenterId'],
          'serviceCenterName': data['serviceCenterName'],
          'serviceCenterContactNumber': serviceCenterContact['phone'],
          'towingType': data['towingType'] ?? 'standard',
          'location': {
            'customer': {
              'address': {
                'full': pickupAddress,
                'street': location['customer']?['address']?['street'],
                'city': location['customer']?['address']?['city'],
                'state': location['customer']?['address']?['state'],
              },
              'coordinates': location['customer']?['coordinates'],
            },
          },
          'address': serviceCenterAddress,
          'vehicleInfo': vehicleInfo,
          'vehiclePlate': vehicleInfo['plateNumber'] ?? 'Unknown',
          'driverId': data['driverId'],
          'driverInfo': driverInfo,
          'driverContactNumber': driverContactNumber,
          'driverVehicleInfo': _safeMapConversion(data['driverVehicleInfo']),
          'distance': (data['distance'] as num?)?.toDouble(),
          'estimatedCost': (data['estimatedCost'] as num?)?.toDouble(),
          'finalCost': (data['finalCost'] as num?)?.toDouble(),
          'totalAmount':
              data['totalAmount'] ??
              (data['finalCost'] as num?)?.toDouble() ??
              (data['estimatedCost'] as num?)?.toDouble() ??
              0.0,
          'description': data['description'] ?? '',
          'email': data['email'] ?? '',
          'createdAt': data['createdAt'] as Timestamp?,
          'updatedAt': data['updatedAt'] as Timestamp?,
          'requestedAt': timestamps['requestedAt'] as Timestamp?,
          'assignedAt': timestamps['driverAssignedAt'] as Timestamp?,
          'dispatchedAt': timestamps['dispatchedAt'] as Timestamp?,
          'completedAt': timestamps['completedAt'] as Timestamp?,
          'paymentStatus': paymentStatus,
          'paymentMethod': paymentMethod,
          'paidAmount': paidAmount,
          'hasPayment': hasPayment,
          'pricingBreakdown': pricingBreakdown,
          'coverageArea': data['coverageArea'],
          'responseTime': data['responseTime'],
          'estimatedDuration': data['estimatedDuration'],
          'statusHistory': data['statusHistory'] ?? [],
          'rating':
              rating.isNotEmpty
                  ? {
                    'stars':
                        rating['serviceRating'] ??
                        rating['driverRating'] ??
                        rating['stars'],
                    'comment': rating['comments'] ?? rating['comment'],
                  }
                  : null,
          'cancellation':
              data['cancellationReason'] != null
                  ? {
                    'reason': data['cancellationReason'],
                    'cancelledBy': data['cancelledBy'] ?? 'customer',
                    'cancelledAt': timestamps['cancelledAt'] as Timestamp?,
                  }
                  : null,
        });
      }
      // Sort by creation date by most recent first
      history.sort((a, b) {
        final aDate = a['createdAt'] as Timestamp?;
        final bDate = b['createdAt'] as Timestamp?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      setState(() {
        _serviceHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load service history: $e';
        _isLoading = false;
      });
      debugPrint('Error loading service history: $e');
    }
  }

  double _calculateTotalAmount(Map<String, dynamic> data) {
    try {
      // Check for total estimated amount first
      if (data['totalEstAmount'] != null && data['totalEstAmount'] > 0) {
        return (data['totalEstAmount'] as num).toDouble();
      }

      // Check for total fixed price
      if (data['totalFixedPrice'] != null && data['totalFixedPrice'] > 0) {
        return (data['totalFixedPrice'] as num).toDouble();
      }

      // Check for range pricing - use min as base
      if (data['totalRangePriceMin'] != null &&
          data['totalRangePriceMin'] > 0) {
        return (data['totalRangePriceMin'] as num).toDouble();
      }

      // Calculate from subtotal + SST
      final subtotal = data['subtotal'] as num?;
      final sst = data['sst'] as num?;

      if (subtotal != null && sst != null) {
        return subtotal.toDouble() + sst.toDouble();
      }

      // Fallback to subtotal only
      if (subtotal != null && subtotal > 0) {
        return subtotal.toDouble();
      }

      return 0.0;
    } catch (e) {
      debugPrint('Error calculating total amount: $e');
      return 0.0;
    }
  }

  String _getDisplayPrice(Map<String, dynamic> data) {
    // Check for range pricing first
    final totalEstAmountRange = data['totalEstAmountRange'] as String?;
    final totalRangePriceMin = data['totalRangePriceMin'] as num?;
    final totalRangePriceMax = data['totalRangePriceMax'] as num?;

    // Check for fixed pricing
    final totalEstAmount = data['totalEstAmount'] as num?;
    final totalFixedPrice = data['totalFixedPrice'] as num?;
    final subtotal = data['subtotal'] as num?;
    final sst = data['sst'] as num?;

    // If there's a range amount string
    if (totalEstAmountRange != null && totalEstAmountRange.isNotEmpty) {
      return totalEstAmountRange;
    }

    // If have min/max range values
    if (totalRangePriceMin != null &&
        totalRangePriceMax != null &&
        totalRangePriceMin > 0 &&
        totalRangePriceMax > totalRangePriceMin) {
      return 'RM${totalRangePriceMin.toStringAsFixed(2)} - RM${totalRangePriceMax.toStringAsFixed(2)}';
    }

    // If have total estimated amount
    if (totalEstAmountRange == null ||
        totalEstAmountRange.isEmpty ||
        totalEstAmountRange == "") {
      if (totalEstAmount != null && totalEstAmount > 0) {
        return 'RM${totalEstAmount.toStringAsFixed(2)}';
      } else if (totalFixedPrice != null && totalFixedPrice > 0) {
        return 'RM${totalFixedPrice.toStringAsFixed(2)}';
      }
    } else {
      return 'RM${totalEstAmount}';
    }

    // If have total fixed price
    if (totalFixedPrice != null && totalFixedPrice > 0) {
      return 'RM${totalFixedPrice.toStringAsFixed(2)}';
    }

    // Calculate from subtotal + SST if available
    if (subtotal != null && sst != null && subtotal > 0) {
      final total = subtotal.toDouble() + sst.toDouble();
      return 'RM${total.toStringAsFixed(2)}';
    }
    return 'RM0.00';
  }

  List<Map<String, dynamic>> _getAllPackages(Map<String, dynamic> data) {
    final package = data['package'] as Map<String, dynamic>?;
    final packages = data['packages'] as List? ?? [];

    List<Map<String, dynamic>> allPackages = [];
    if (package != null) allPackages.add(package);
    if (packages.isNotEmpty) {
      allPackages.addAll(packages.cast<Map<String, dynamic>>());
    }
    return allPackages;
  }

  Map<String, dynamic> _safeMapConversion(dynamic value) {
    if (value == null) return <String, dynamic>{};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Future<String> _getServiceCenterName(String? id) async {
    if (id == null) return 'Unknown Service Center';
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(id)
              .get();
      if (doc.exists) {
        final data = doc.data()!;
        final serviceCenterInfo =
            data['serviceCenterInfo'] as Map<String, dynamic>?;
        return serviceCenterInfo?['name'] ?? 'Unknown Service Center';
      }
    } catch (_) {}
    return 'Unknown Service Center';
  }

  Future<String> _getServiceCenterContactNumber(String? id) async {
    if (id == null) return 'N/A';
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(id)
              .get();
      if (doc.exists) {
        final data = doc.data()!;
        final serviceCenterInfo =
            data['serviceCenterInfo'] as Map<String, dynamic>?;
        return serviceCenterInfo?['serviceCenterPhoneNo'] ?? 'N/A';
      }
    } catch (_) {}
    return 'N/A';
  }

  List<Map<String, dynamic>> _getFilteredHistory() {
    List<Map<String, dynamic>> filtered = _serviceHistory;

    // Service Type filter
    if (_selectedServiceType != 'all') {
      filtered =
          filtered
              .where((item) => item['type'] == _selectedServiceType)
              .toList();
    }

    // Vehicle filter
    if (_selectedVehicle != 'all') {
      filtered =
          filtered
              .where((item) => item['vehiclePlate'] == _selectedVehicle)
              .toList();
    }

    // Time filter
    final now = DateTime.now();
    if (_selectedTimeFilter != 'all') {
      filtered =
          filtered.where((item) {
            final createdAt = item['createdAt'] as Timestamp?;
            if (createdAt == null) return false;

            final date = createdAt.toDate();
            switch (_selectedTimeFilter) {
              case 'today':
                return date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
              case 'week':
                final weekAgo = now.subtract(const Duration(days: 7));
                return date.isAfter(weekAgo);
              case 'month':
                final monthAgo = now.subtract(const Duration(days: 30));
                return date.isAfter(monthAgo);
              default:
                return true;
            }
          }).toList();
    }

    return filtered;
  }

  List<Map<String, dynamic>> _getTabHistory(int tabIndex) {
    final filtered = _getFilteredHistory();

    switch (tabIndex) {
      case 0:
        return filtered;
      case 1:
        return filtered
            .where(
              (item) => [
                'pending',
                'confirmed',
                'assigned',
                'in_progress',
                'dispatched',
              ].contains(item['status']),
            )
            .toList();
      case 2: // Ready
        return filtered
            .where((item) => item['status'] == 'ready_to_collect')
            .toList();
      case 3: // Completed
        return filtered.where((item) => item['status'] == 'completed').toList();
      case 4: // Cancelled/Declined
        return filtered
            .where((item) => ['cancelled', 'declined'].contains(item['status']))
            .toList();
      default:
        return filtered;
    }
  }

  String formatDate(Timestamp? ts) {
    if (ts == null) return 'N/A';
    return DateFormat('dd MMM, yyyy').format(ts.toDate());
  }

  String formatDateTime(Timestamp? ts) {
    if (ts == null) return 'N/A';
    return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Not yet';
    return DateFormat('dd MMM yyyy, HH:mm').format(timestamp.toDate());
  }

  String _formatDuration(int? minutes) {
    if (minutes == null || minutes <= 0) return 'Not specified';

    if (minutes < 60) {
      return '$minutes mins';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;

      if (remainingMinutes == 0) {
        return '$hours ${hours == 1 ? 'hour' : 'hours'}';
      } else {
        return '$hours ${hours == 1 ? 'hour' : 'hours'} $remainingMinutes mins';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFilterSection(),
          // Main Content
          Expanded(
            child:
                _isLoading
                    ? _buildLoadingState()
                    : _error != null
                    ? _buildErrorState()
                    : _serviceHistory.isEmpty
                    ? _buildEmptyState()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.secondaryColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Service History',
        style: TextStyle(
          color: AppColors.secondaryColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.refresh,
              color: AppColors.secondaryColor,
              size: 20,
            ),
          ),
          onPressed: _loadServiceHistory,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppColors.primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: AppColors.primaryColor,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        isScrollable: true,
        tabs: [
          Tab(text: 'All (${_getTabHistory(0).length})'),
          Tab(text: 'Active (${_getTabHistory(1).length})'),
          Tab(text: 'Ready (${_getTabHistory(2).length})'),
          Tab(text: 'Completed (${_getTabHistory(3).length})'),
          Tab(text: 'Cancelled (${_getTabHistory(4).length})'),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      color: AppColors.cardColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Service Type and Vehicle Filters
          Row(
            children: [
              // Service Type Filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedServiceType,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      items: [
                        _buildDropdownItem('all', 'All Services'),
                        _buildDropdownItem('service', 'Service Appointments'),
                        _buildDropdownItem('towing', 'Towing Requests'),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedServiceType = value!;
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Vehicle Filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedVehicle,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      items:
                          _userVehicles.map((vehicle) {
                            return _buildDropdownItem(
                              vehicle,
                              vehicle == 'all' ? 'All Vehicles' : vehicle,
                            );
                          }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedVehicle = value!;
                        });
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Time Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTimeFilter,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                items: [
                  _buildDropdownItem('all', 'All Time'),
                  _buildDropdownItem('today', 'Today'),
                  _buildDropdownItem('week', 'Past Week'),
                  _buildDropdownItem('month', 'Past Month'),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTimeFilter = value!;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _buildDropdownItem(String value, String text) {
    return DropdownMenuItem(
      value: value,
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primaryColor),
          SizedBox(height: 16),
          Text(
            'Loading service history...',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadServiceHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No Service History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You haven\'t booked any services yet.\nStart by finding a workshop near you!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed:
                  () => Navigator.pushNamed(
                    context,
                    'search-service-center',
                    arguments: {
                      'userId': widget.userId,
                      'userName': widget.userName,
                      'userEmail': widget.userEmail,
                    },
                  ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Find Workshop'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildHistoryList(_getTabHistory(0)),
        _buildHistoryList(_getTabHistory(1)),
        _buildHistoryList(_getTabHistory(2)),
        _buildHistoryList(_getTabHistory(3)),
        _buildHistoryList(_getTabHistory(4)),
      ],
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No bookings found',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryColor,
      onRefresh: _loadServiceHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return item['type'] == 'service'
              ? _buildServiceCard(item)
              : _buildTowingCard(item);
        },
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> booking) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('service_bookings')
              .doc(booking['id'] as String)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildServiceCardContent(booking);
        }

        if (snapshot.hasError) {
          debugPrint('Stream error: ${snapshot.error}');
          return _buildServiceCardContent(booking);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildServiceCardContent(booking);
        }

        final latestData = snapshot.data!.data() as Map<String, dynamic>?;
        if (latestData == null) {
          return _buildServiceCardContent(booking);
        }

        // Create updated booking with real-time data but preserve computed fields
        final updatedBooking = Map<String, dynamic>.from(booking);

        // Update only the fields that change in real-time
        updatedBooking['status'] = latestData['status'] ?? booking['status'];
        updatedBooking['updatedAt'] =
            latestData['updatedAt'] ?? booking['updatedAt'];

        // Update payment status
        if (latestData['payment'] != null) {
          updatedBooking['paymentStatus'] =
              latestData['payment']['paymentStatus'] ??
              latestData['payment']['status'];
        }

        // Update status history if available
        if (latestData['statusHistory'] != null) {
          updatedBooking['statusHistory'] = latestData['statusHistory'];
        }

        // Update timestamps if available
        if (latestData['timestamps'] != null) {
          updatedBooking['timestamps'] = latestData['timestamps'];
        }

        // Update invoice ID if generated
        if (latestData['invoiceId'] != null) {
          updatedBooking['invoiceId'] = latestData['invoiceId'];
        }

        // Update rating if added
        if (latestData['rating'] != null) {
          updatedBooking['rating'] = latestData['rating'];
        }

        // Update cancellation if exists
        if (latestData['cancellation'] != null) {
          updatedBooking['cancellation'] = latestData['cancellation'];
        }

        return _buildServiceCardContent(updatedBooking);
      },
    );
  }

  Widget _buildServiceCardContent(Map<String, dynamic> booking) {
    final status = booking['status'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final isActive = [
      'pending',
      'confirmed',
      'assigned',
      'in_progress',
    ].contains(status);
    final isCompleted = status == 'completed';
    final hasRating = booking['rating'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          // Header with status and actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const Spacer(),

                // Service Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'SERVICE',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Date
                Text(
                  formatDate(booking['createdAt'] as Timestamp?),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service Center
                Row(
                  children: [
                    Icon(Icons.business, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (booking['serviceCenterName'] as String?) ??
                            'Unknown Service Center',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Vehicle Information
                if (booking['vehicle'] != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(booking['vehicle'] as Map<String, dynamic>)['make'] ?? ''} ${(booking['vehicle'] as Map<String, dynamic>)['model'] ?? ''} • ${booking['vehiclePlate'] ?? 'Unknown'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Service Summary
                Row(
                  children: [
                    Icon(Icons.build, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getServiceSummary(booking),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Progress indicators for active services
                if (isActive) _buildServiceProgress(booking),
                const SizedBox(height: 12),
                // Price and additional info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Est.Total Amount:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _getDisplayPrice(booking),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),

                      if (booking['paymentStatus'] != null &&
                          (booking['status'] != 'cancelled' &&
                              booking['status'] != 'declined')) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Payment:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getPaymentStatusColor(
                                  booking['paymentStatus'] as String? ??
                                      'unpaid',
                                ),
                              ),
                            ),
                            Text(
                              _getPaymentStatusText(
                                booking['paymentStatus'] as String? ?? 'unpaid',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getPaymentStatusColor(
                                  booking['paymentStatus'] as String? ??
                                      'unpaid',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (booking['hasPayment'] == true &&
                            (booking['paidAmount'] as double) > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Paid Amount:',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'RM${booking['paidAmount'].toString()}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Details button
                TextButton(
                  onPressed: () => _showServiceDetails(booking),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    backgroundColor: AppColors.primaryColor.withOpacity(0.1),
                  ),
                  child: const Text('View Details'),
                ),
                Row(
                  children: [
                    if (isCompleted && !hasRating)
                      IconButton(
                        onPressed: () => _showReviewDialog(booking),
                        icon: const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 20,
                        ),
                        tooltip: 'Add Review',
                      ),

                    // Invoice button for completed services
                    if (isCompleted && booking['invoiceId'] != null)
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ServiceInvoicePage(
                                    invoiceId: booking['invoiceId'] as String,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.receipt,
                          color: Colors.blue,
                          size: 20,
                        ),
                        tooltip: 'View Invoice',
                      ),

                    // Invoice button for completed services
                    if (isCompleted && booking['receiptId'] != null) ...[
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ServiceReceiptPage(
                                    receiptId: booking['receiptId'] as String,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.receipt_long,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        tooltip: 'View Receipt',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showServiceDetails(Map<String, dynamic> booking) {
    final packagesList = booking['packages'] as List? ?? [];
    final servicesList = booking['services'] as List? ?? [];
    final selectionType = booking['selectionType'] as String?;
    final status = booking['status'] as String? ?? 'unknown';
    final isActive = [
      'pending',
      'confirmed',
      'assigned',
      'in_progress',
    ].contains(status);
    final isCompleted = status == 'completed';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header with Status
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Service Booking Details',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryColor
                                              .withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'SERVICE',
                                          style: TextStyle(
                                            color: AppColors.primaryColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                      ),

                      // Progress Indicator for Active Services
                      if (isActive) _buildDetailedProgressIndicator(booking),

                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildQuickInfoSection(booking),
                              const SizedBox(height: 20),
                              _buildServiceCenterSection(booking),
                              const SizedBox(height: 20),
                              _buildVehicleSection(booking),
                              const SizedBox(height: 20),
                              // Services & Packages
                              _buildServicesSection(
                                booking,
                                packagesList,
                                servicesList,
                                selectionType,
                              ),
                              const SizedBox(height: 6),
                              _buildPaymentSection(booking),
                              const SizedBox(height: 10),
                              _buildServiceMaintenances(booking),
                              const SizedBox(height: 10),
                              _buildStatusUpdateTimeline(booking),
                              const SizedBox(height: 10),

                              // Action buttons based on status
                              if (booking['status'] == 'pending' ||
                                  booking['status'] == 'approved') ...[
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: OutlinedButton(
                                    onPressed:
                                        () => _cancelAppointment(booking),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.errorColor,
                                      side: BorderSide(
                                        color: AppColors.errorColor,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Cancel Appointment'),
                                  ),
                                ),
                              ],

                              if (isCompleted) _buildRatingSection(booking),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),

                      // Action Buttons
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Invoice Button for completed services
                            if (isCompleted && booking['invoiceId'] != null)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => ServiceInvoicePage(
                                              invoiceId:
                                                  booking['invoiceId']
                                                      as String,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.receipt, size: 18),
                                  label: const Text('View Invoice'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 16),
                            if (isCompleted &&
                                booking['receiptId'] != null) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => ServiceReceiptPage(
                                              receiptId:
                                                  booking['receiptId']
                                                      as String,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 18,
                                  ),
                                  label: const Text('View Receipt'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  // Service booking progress details
  Widget _buildDetailedProgressIndicator(Map<String, dynamic> booking) {
    final status = booking['status'] as String? ?? 'unknown';
    final steps = [
      {
        'status': 'pending',
        'label': 'Pending',
        'icon': Icons.pending,
        'description': 'Waiting for confirmation',
      },
      {
        'status': 'confirmed',
        'label': 'Confirmed',
        'icon': Icons.check_circle_outline,
        'description': 'Appointment confirmed',
      },
      {
        'status': 'assigned',
        'label': 'Assigned',
        'icon': Icons.person_outline,
        'description': 'Technician assigned',
      },
      {
        'status': 'in_progress',
        'label': 'In Progress',
        'icon': Icons.build,
        'description': 'Service in progress',
      },
      {
        'status': ['ready_to_collect', 'invoice_generated'],
        'label': 'Ready',
        'icon': Icons.emoji_transportation,
        'description': 'Ready for collection',
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.backgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service Progress',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children:
                steps.asMap().entries.map((entry) {
                  final index = entry.key;
                  final step = entry.value;
                  final isCompleted = index <= currentIndex;
                  final isCurrent = index == currentIndex;

                  return Expanded(
                    child: Column(
                      children: [
                        // Connection line
                        Container(
                          height: 3,
                          color:
                              isCompleted
                                  ? AppColors.primaryColor
                                  : Colors.grey.shade300,
                        ),
                        const SizedBox(height: 8),

                        // Icon and status
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color:
                                    isCompleted
                                        ? AppColors.primaryColor
                                        : Colors.grey.shade300,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                step['icon'] as IconData,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            if (isCurrent)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Label
                        Text(
                          step['label'] as String,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isCurrent ? FontWeight.bold : FontWeight.normal,
                            color:
                                isCompleted
                                    ? AppColors.primaryColor
                                    : Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),

          // Current status description
          if (currentIndex >= 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.secondaryColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[currentIndex]['description'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickInfoSection(Map<String, dynamic> booking) {
    return Row(
      children: [
        // Booking ID
        Expanded(
          child: _buildInfoCard(
            icon: Icons.confirmation_number,
            title: 'Booking ID',
            value: (booking['id']?.toString().substring(0, 8)) ?? 'N/A',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),

        // Urgency Level
        Expanded(
          child: _buildInfoCard(
            icon: Icons.priority_high,
            title: 'Priority',
            value:
                ((booking['urgencyLevel'] as String?) ?? 'normal')
                    .toUpperCase(),
            color:
                booking['urgencyLevel'] == 'emergency'
                    ? Colors.red
                    : Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCenterSection(Map<String, dynamic> booking) {
    return Container(
      width: double.infinity,
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
              Icon(Icons.business, size: 20, color: AppColors.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Service Center',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailItem(
            'Name',
            (booking['serviceCenterName'] as String?) ?? 'Unknown',
          ),
          _buildDetailItem(
            'Contact',
            (booking['contactNumber'] as String?) ?? 'N/A',
          ),
          if (booking['scheduledDate'] != null)
            _buildDetailItem(
              'Scheduled',
              '${formatDate(booking['scheduledDate'] as Timestamp?)}${booking['scheduledTime'] != null ? ' at ${booking['scheduledTime']}' : ''}',
            ),
          _buildDetailItem(
            'Duration',
            _formatDuration(booking['estimatedDuration'] as int?),
          ),
          _buildDetailItem(
            'Notes',
            (booking['notes'] as String?) ?? 'No additional notes',
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection(Map<String, dynamic> booking) {
    final vehicle = (booking['vehicle'] as Map<String, dynamic>?) ?? {};
    return Container(
      width: double.infinity,
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
              Icon(
                Icons.directions_car,
                size: 20,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                'Vehicle Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${(booking['vehicle'] as Map<String, dynamic>)['make'] ?? ''} ${(booking['vehicle'] as Map<String, dynamic>)['model'] ?? ''} • ${booking['vehiclePlate'] ?? 'Unknown'}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'Mileage: ${booking['currentMileage']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${booking['vehicle']['sizeClass']}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesSection(
    Map<String, dynamic> booking,
    List packagesList,
    List servicesList,
    String? selectionType,
  ) {
    final hasPackages = packagesList.isNotEmpty;
    final hasServices = servicesList.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Services & Packages',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),

        // Individual Services
        if (hasServices) ...[
          Row(
            children: [
              Icon(
                Icons.build_rounded,
                size: 20,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                'Booked Services',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.secondaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          ...servicesList
              .map(
                (service) =>
                    _buildServiceItemCard(service as Map<String, dynamic>),
              )
              .toList(),
        ],

        // Packages
        if (hasPackages) ...[
          ...packagesList
              .map(
                (package) => _buildPackageCard(package as Map<String, dynamic>),
              )
              .toList(),
          const SizedBox(height: 16),
        ],

        // Empty state
        if (!hasPackages && !hasServices)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'No services details available',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> package) {
    final packageServices = package['services'] as List? ?? [];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // color: AppColors.secondaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.secondaryColor.withOpacity(0.2)),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.inventory_2, size: 20, color: AppColors.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (package['packageName'] as String?) ?? 'Service Package',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    if (package['description'] != null &&
                        (package['description'] as String).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        package['description'] as String,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Included Services
          if (packageServices.isNotEmpty) ...[
            Text(
              'Includes ${packageServices.length} services:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children:
                  packageServices.map((service) {
                    final serviceMap = service as Map<String, dynamic>;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Text(
                        (serviceMap['serviceName'] as String?) ?? 'Service',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Package Pricing
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Package Price:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _getServicePrice(package),
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryColor,
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

  Widget _buildServiceItemCard(Map<String, dynamic> service) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (service['serviceName'] as String?) ?? 'Service',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Service Price:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
              Text(
                _getServicePrice(service),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection(Map<String, dynamic> booking) {
    final subtotal = booking['subtotal'] as num?;
    final sst = booking['sst'] as num?;
    final subtotalRange = booking['subtotalRange'] as String?;
    final sstRange = booking['sstRange'] as String?;

    return Container(
      width: double.infinity,
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
          // Header
          Row(
            children: [
              Icon(Icons.payment, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Payment Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Column(
            children: [
              // Subtotal
              if (subtotalRange != null && subtotalRange.isNotEmpty)
                _buildCompactPriceRow('Subtotal', subtotalRange),
              if (subtotal != null &&
                  (subtotalRange == null || subtotalRange.isEmpty))
                _buildCompactPriceRow(
                  'Subtotal',
                  'RM${subtotal.toStringAsFixed(2)}',
                ),

              // SST
              if (sstRange != null && sstRange.isNotEmpty)
                _buildCompactPriceRow('SST (8%)', sstRange),
              if (sst != null && (sstRange == null || sstRange.isEmpty))
                _buildCompactPriceRow(
                  'SST (8%)',
                  'RM${sst.toStringAsFixed(2)}',
                ),

              // Total with divider
              if ((subtotal != null || subtotalRange != null) ||
                  (sst != null || sstRange != null))
                const Divider(height: 12, thickness: 1),

              _buildCompactTotalRow(
                'Est.Total Amount',
                _getDisplayPrice(booking),
              ),
            ],
          ),

          const SizedBox(height: 12),
          if (booking['paymentStatus'] != null &&
              (booking['status'] != 'cancelled' &&
                  booking['status'] != 'declined')) ...[
            Row(
              children: [
                Expanded(
                  child: _buildCompactPaymentDetail(
                    'Status',
                    _getPaymentStatusText(
                      booking['paymentStatus'] as String? ?? 'unpaid',
                    ),
                    _getPaymentStatusColor(
                      booking['paymentStatus'] as String? ?? 'unpaid',
                    ),
                  ),
                ),
                const SizedBox(width: 30),
                Expanded(
                  child: _buildCompactPaymentDetail(
                    'Method',
                    (booking['paymentMethod'] ?? 'N/A').toUpperCase(),
                    Colors.grey.shade700,
                  ),
                ),
                if (booking['hasPayment'] == true &&
                    (booking['paidAmount'] as double) > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildCompactPaymentDetail(
                      'Paid Amount',
                      'RM${booking['paidAmount'].toString()}',
                      AppColors.primaryColor,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactPriceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTotalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.secondaryColor,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactPaymentDetail(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceMaintenances(Map<String, dynamic> booking) {
    final serviceMaintenances = booking['serviceMaintenances'] as List? ?? [];

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
            'Service Maintenance Schedule',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...serviceMaintenances
              .map<Widget>((maintenance) => _buildMaintenanceRow(maintenance))
              .toList(),
        ],
      ),
    );
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

  Widget _buildStatusUpdateTimeline(Map<String, dynamic> booking) {
    final statusHistory = booking['statusHistory'] ?? [];

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
                (history) => _buildServiceTimelineItem(
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

  Widget _buildServiceTimelineItem(
    String status,
    Timestamp timestamp,
    String notes,
  ) {
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

  void _cancelAppointment(Map<String, dynamic> booking) {
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
                            .doc(booking['id'] as String)
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

                    await FirebaseFirestore.instance
                        .collection('service_bookings')
                        .doc(booking['id'] as String)
                        .update(bookingUpdate);

                    // Close loading indicator
                    if (mounted) Navigator.pop(context);

                    // Show success message
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Appointment cancelled successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }

                    // Reload the service history to reflect changes
                    if (mounted) {
                      await _loadServiceHistory();
                    }
                  } catch (e) {
                    // Close loading indicator if still open
                    if (mounted) Navigator.pop(context);

                    // Show error message with actual error
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Failed to cancel appointment: ${e.toString()}',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    debugPrint('Error cancelling appointment: $e');
                  }
                },
                child: const Text('Yes, Cancel'),
              ),
            ],
          ),
    );
  }

  Widget _buildRatingSection(Map<String, dynamic> booking) {
    final rating = booking['rating'] as Map<String, dynamic>?;
    final hasRating =
        rating != null && rating.isNotEmpty && rating['stars'] != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasRating ? Colors.green.shade50 : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasRating ? Colors.green.shade200 : Colors.amber.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasRating ? Icons.star : Icons.star_outline,
                size: 20,
                color: hasRating ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                hasRating ? 'Your Rating' : 'Rate Your Experience',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (hasRating) ...[
            Row(
              children: [
                for (int i = 0; i < 5; i++)
                  Icon(
                    i < ((rating!['stars'] as num?)?.toInt() ?? 0)
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 20,
                  ),
                const SizedBox(width: 8),
                Text(
                  '${rating['stars']}/5',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            if (rating['comment'] != null &&
                (rating['comment'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                rating['comment'] as String,
                style: TextStyle(color: Colors.green.shade700, fontSize: 14),
              ),
            ],
          ] else ...[
            Text(
              'Share your experience with this service',
              style: TextStyle(color: Colors.amber.shade700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showReviewDialog(booking),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Review'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getServicePrice(Map<String, dynamic> service) {
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

  Future<void> _updateServiceCenterRating(String serviceCenterId) async {
    try {
      // Query reviews from the dedicated reviews collection
      final reviewsSnapshot =
          await FirebaseFirestore.instance
              .collection('reviews')
              .where('serviceCenterId', isEqualTo: serviceCenterId)
              .where('status', isEqualTo: 'approved')
              .get();

      if (reviewsSnapshot.docs.isNotEmpty) {
        double totalRating = 0;
        int reviewCount = 0;

        for (var doc in reviewsSnapshot.docs) {
          final data = doc.data();
          if (data['rating'] != null) {
            totalRating += (data['rating'] as num).toDouble();
            reviewCount++;
          }
        }

        final averageRating = totalRating / reviewCount;

        await FirebaseFirestore.instance
            .collection('service_centers')
            .doc(serviceCenterId)
            .update({
              'averageRating': double.parse(averageRating.toStringAsFixed(1)),
              'totalReviews': reviewCount,
              'updatedAt': FieldValue.serverTimestamp(),
            });

        debugPrint(
          'Successfully updated service center $serviceCenterId with rating: $averageRating and reviews: $reviewCount',
        );
      }
    } catch (e) {
      debugPrint('Error updating service center rating: $e');
    }
  }

  Widget _buildTowingCard(Map<String, dynamic> towing) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('towing_requests')
              .doc(towing['id'] as String)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTowingCardContent(towing);
        }

        if (snapshot.hasError) {
          debugPrint('Towing stream error: ${snapshot.error}');
          return _buildTowingCardContent(towing);
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildTowingCardContent(towing);
        }

        final latestData = snapshot.data!.data() as Map<String, dynamic>?;
        if (latestData == null) {
          return _buildTowingCardContent(towing);
        }

        // Create updated towing with real-time data but preserve computed fields
        final updatedTowing = Map<String, dynamic>.from(towing);

        // Update only the fields that change in real-time
        updatedTowing['status'] = latestData['status'] ?? towing['status'];
        updatedTowing['updatedAt'] =
            latestData['updatedAt'] ?? towing['updatedAt'];

        // Update driver info if available
        if (latestData['driverInfo'] != null) {
          updatedTowing['driverInfo'] = latestData['driverInfo'];
        }

        // Update timestamps if available
        if (latestData['timestamps'] != null) {
          updatedTowing['timestamps'] = latestData['timestamps'];
        }

        // Update status history if available
        if (latestData['statusHistory'] != null) {
          updatedTowing['statusHistory'] = latestData['statusHistory'];
        }

        return _buildTowingCardContent(updatedTowing);
      },
    );
  }

  Widget _buildTowingCardContent(Map<String, dynamic> towing) {
    final status = towing['status'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final isActive = [
      'pending',
      'accepted',
      'assigned',
      'dispatched',
      'ongoing',
    ].contains(status);
    final isCompleted = status == 'completed';
    final hasRating = towing['rating'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          // Header with status and actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const Spacer(),

                // Service Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'TOWING',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Date
                Text(
                  formatDate(towing['createdAt'] as Timestamp?),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service Center
                Row(
                  children: [
                    Icon(Icons.business, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        towing['serviceCenterName'] ?? 'Service Center',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Vehicle Information
                if (towing['vehicleInfo'] != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(towing['vehicleInfo'] as Map<String, dynamic>)['make'] ?? ''} ${(towing['vehicleInfo'] as Map<String, dynamic>)['model'] ?? ''} • ${(towing['vehicleInfo'] as Map<String, dynamic>)['plateNumber'] ?? 'Unknown'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Towing Type
                Row(
                  children: [
                    Icon(
                      Icons.local_shipping,
                      size: 16,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        towing['towingType'] ?? 'General Towing',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Progress indicators for active towing
                if (isActive) _buildTowingProgress(towing),

                // Cost and additional info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated Cost:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _getTowingDisplayPrice(towing),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),

                      if (towing['distance'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Distance:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(towing['distance'] as num).toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      if (towing['paymentStatus'] != null &&
                          (towing['status'] != 'cancelled' &&
                              towing['status'] != 'declined')) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Payment:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _getPaymentStatusColor(
                                  towing['paymentStatus'] as String? ??
                                      'unpaid',
                                ),
                              ),
                            ),
                            Text(
                              _getPaymentStatusText(
                                towing['paymentStatus'] as String? ?? 'unpaid',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _getPaymentStatusColor(
                                  towing['paymentStatus'] as String? ??
                                      'unpaid',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (towing['hasPayment'] == true &&
                            (towing['paidAmount'] as double) > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Paid Amount:',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'RM${towing['paidAmount'].toString()}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Details button
                TextButton(
                  onPressed: () => _showTowingDetails(towing),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    backgroundColor: AppColors.primaryColor.withOpacity(0.1),
                  ),
                  child: const Text('View Details'),
                ),
                Row(
                  children: [
                    if (isCompleted && !hasRating)
                      IconButton(
                        onPressed: () => _showReviewDialog(towing),
                        icon: const Icon(
                          Icons.star,
                          color: Colors.amber,
                          size: 20,
                        ),
                        tooltip: 'Add Review',
                      ),

                    if (towing['invoiceId'] != null)
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => TowingInvoicePage(
                                    invoiceId: towing['invoiceId'] as String,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.receipt,
                          color: Colors.blue,
                          size: 20,
                        ),
                        tooltip: 'View Invoice',
                      ),

                    if (isCompleted && towing['receiptId'] != null) ...[
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => TowingReceiptPage(
                                    receiptId: towing['receiptId'] as String,
                                  ),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.receipt_long,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        tooltip: 'View Receipt',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTowingDetails(Map<String, dynamic> towing) {
    final status = towing['status'] as String? ?? 'unknown';
    final isActive = [
      'pending',
      'accepted',
      'dispatched',
      'ongoing',
    ].contains(status);
    final isCompleted = status == 'completed';
    final hasRating = towing['rating'] != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: AppColors.cardColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header with Status
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Towing Request Details',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'TOWING',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                      ),

                      // Progress Indicator for Active Towing
                      if (isActive) _buildTowingProgressInfo(towing),

                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTowingRequestQuickInfoSection(towing),

                              // Driver Information (if available)
                              if (towing['driverInfo'] != null &&
                                  towing['driverInfo'].isNotEmpty)
                                _buildDriverCard(towing),

                              if (towing['driverInfo'] != null &&
                                  towing['driverInfo'].isNotEmpty)
                                const SizedBox(height: 20),

                              // Service Center Information
                              _buildServiceCenterCard(towing),

                              const SizedBox(height: 20),

                              // Vehicle Information
                              _buildVehicleCard(towing),

                              const SizedBox(height: 20),

                              // Pricing & Distance Information
                              if (towing['pricingBreakdown'] != null) ...[
                                _buildPricingCard(towing),
                                const SizedBox(height: 20),
                              ],

                              // Location Information
                              if (towing['location'] != null) ...[
                                _buildLocationCard(towing),
                                const SizedBox(height: 20),
                              ],
                              _buildServiceDetailsCard(towing),
                              const SizedBox(height: 20),

                              _buildTowingPaymentInfoCard(towing),
                              const SizedBox(height: 20),

                              _buildStatusTimeline(towing),
                              const SizedBox(height: 20),

                              if (isCompleted) _buildRatingSection(towing),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),

                      // Action Buttons
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Review Button for completed towing without rating
                            if (isCompleted && !hasRating) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showReviewDialog(towing),
                                  icon: const Icon(Icons.star, size: 18),
                                  label: const Text('Rate Service'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            // Cancel button for pending requests
                            if (status == 'pending') ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _cancelTowingRequest(towing),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.errorColor,
                                    side: BorderSide(
                                      color: AppColors.errorColor,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Cancel Request'),
                                ),
                              ),
                            ],

                            if (towing['invoiceId'] != null) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => TowingInvoicePage(
                                              invoiceId:
                                                  towing['invoiceId'] as String,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.receipt, size: 18),
                                  label: const Text('View Invoice'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 16),
                            if (isCompleted && towing['receiptId'] != null) ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => TowingReceiptPage(
                                              receiptId:
                                                  towing['receiptId'] as String,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.receipt_long,
                                    size: 18,
                                  ),
                                  label: const Text('View Receipt'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildTowingRequestQuickInfoSection(Map<String, dynamic> towing) {
    return Row(
      children: [
        // Booking ID
        Expanded(
          child: _buildInfoCard(
            icon: Icons.confirmation_number,
            title: 'Towing Request ID',
            value: (towing['id']?.toString().substring(0, 8)) ?? 'N/A',
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildDriverCard(Map<String, dynamic> towing) {
    final driverInfo = _safeMapConversion(towing['driverInfo']);

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
              Icon(Icons.person, color: AppColors.primaryColor, size: 20),
              const Text(
                'Driver Information',
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Driver Avatar
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: _buildDriverImage(driverInfo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverInfo['name'] ?? 'Unknown Driver',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (driverInfo['rating'] != null)
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            driverInfo['rating'].toString(),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (driverInfo['contactNumber'] != null)
                IconButton(
                  onPressed: () => _makeCall(driverInfo['contactNumber']),
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

          // Driver Vehicle Information
          if (towing['driverVehicleInfo'] != null) ...[
            const SizedBox(height: 16),
            _buildDriverVehicleInfo(towing),
          ],
        ],
      ),
    );
  }

  Widget _buildDriverImage(Map<String, dynamic> driverInfo) {
    final driverImage = driverInfo['driverImage'];

    if (driverImage == null || driverImage.toString().isEmpty) {
      return const Icon(Icons.person, color: AppColors.primaryColor, size: 30);
    }

    try {
      // Try to handle encrypted image
      const secretKey = "AUTO_MATE_SECRET_KEY_256";
      final decryptedImage = CryptoJSCompat.decrypt(
        driverImage.toString(),
        secretKey,
      );

      if (decryptedImage.isNotEmpty && decryptedImage.startsWith('data:')) {
        return _buildBase64Image(decryptedImage);
      }
    } catch (e) {
      debugPrint('Error decrypting driver image: $e');
    }

    // Fallback to default icon
    return const Icon(Icons.person, color: AppColors.primaryColor, size: 30);
  }

  Widget _buildBase64Image(String dataUri) {
    try {
      final base64String = dataUri.split(',').last;
      final bytes = base64.decode(base64String);

      return ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.memory(
          bytes,
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
    } catch (e) {
      return const Icon(Icons.person, color: AppColors.primaryColor, size: 30);
    }
  }

  Widget _buildDriverVehicleInfo(Map<String, dynamic> towing) {
    final driverVehicleInfo = towing['driverVehicleInfo'];

    if (driverVehicleInfo == null) return Container();

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
            child: _buildVehicleImage(driverVehicleInfo),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleImage(Map<String, dynamic> driverVehicleInfo) {
    final vehicleImages = driverVehicleInfo['vehicleImage'];

    if (vehicleImages == null ||
        vehicleImages is! List ||
        vehicleImages.isEmpty) {
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

      if (decryptedImage.isNotEmpty && decryptedImage.startsWith('data:')) {
        return _buildVehicleBase64Image(decryptedImage);
      }
    } catch (e) {
      debugPrint('Error decrypting vehicle image: $e');
    }

    return const Icon(
      Icons.directions_car,
      color: AppColors.primaryColor,
      size: 24,
    );
  }

  Widget _buildVehicleBase64Image(String dataUri) {
    try {
      final base64String = dataUri.split(',').last.trim();
      final bytes = base64.decode(base64String);

      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 60,
          height: 60,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.directions_car,
              color: AppColors.primaryColor,
              size: 24,
            );
          },
        ),
      );
    } catch (e) {
      return const Icon(
        Icons.directions_car,
        color: AppColors.primaryColor,
        size: 24,
      );
    }
  }

  Widget _buildServiceCenterCard(Map<String, dynamic> towing) {
    final serviceCenterName =
        towing['serviceCenterName'] ?? 'Unknown Service Center';
    final contactNumber = towing['serviceCenterContactNumber'] ?? 'N/A';

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(
                Icons.business,
                color: AppColors.primaryColor,
                size: 20,
              ),
              const Text(
                'Service Center Information',
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (contactNumber != 'N/A' && contactNumber.isNotEmpty)
                IconButton(
                  onPressed: () => _makeCall(contactNumber),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceCenterName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (towing['address'] != null) ...[
                      Text(
                        towing['address'].toString(),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      Text(
                        'Address not available',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> towing) {
    final vehicleInfo = _safeMapConversion(towing['vehicleInfo']);

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
            'Vehicle Information',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (vehicleInfo.isNotEmpty) ...[
            _buildDetailRow('Make', vehicleInfo['make'] ?? 'N/A'),
            _buildDetailRow('Model', vehicleInfo['model'] ?? 'N/A'),
            _buildDetailRow('Year', vehicleInfo['year'] ?? 'N/A'),
            _buildDetailRow(
              'Plate Number',
              vehicleInfo['plateNumber'] ?? 'N/A',
            ),
            _buildDetailRow('Size Class', vehicleInfo['sizeClass'] ?? 'N/A'),
          ],
        ],
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
            width: 120,
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

  Widget _buildTowingProgress(Map<String, dynamic> towing) {
    final status = towing['status'] as String? ?? 'unknown';
    final steps = [
      {'status': 'pending', 'label': 'Pending', 'icon': Icons.pending},
      {
        'status': 'accepted',
        'label': 'Accepted',
        'icon': Icons.check_circle_outline,
      },
      {
        'status': 'dispatched',
        'label': 'Dispatched',
        'icon': Icons.local_shipping,
      },
      {'status': 'ongoing', 'label': 'Ongoing', 'icon': Icons.build},
      {
        'status': 'invoice_generated',
        'label': 'Ready',
        'icon': Icons.emoji_transportation,
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Current Status:',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children:
              steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                final isCompleted = index <= currentIndex;
                final isCurrent = index == currentIndex;

                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 3,
                              color:
                                  isCompleted
                                      ? Colors.orange
                                      : Colors.grey.shade300,
                            ),
                          ),
                          if (index < steps.length - 1)
                            const SizedBox(width: 4),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        step['icon'] as IconData,
                        size: 16,
                        color:
                            isCompleted ? Colors.orange : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              isCompleted
                                  ? Colors.orange
                                  : Colors.grey.shade500,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Widget _buildTowingProgressInfo(Map<String, dynamic> towing) {
    final status = towing['status'] as String? ?? 'unknown';
    final steps = [
      {
        'status': 'pending',
        'label': 'Pending',
        'icon': Icons.pending,
        'description': 'Request submitted and awaiting confirmation',
      },
      {
        'status': 'accepted',
        'label': 'Accepted',
        'icon': Icons.check_circle_outline,
        'description': 'Towing request has been accepted',
      },
      {
        'status': 'dispatched',
        'label': 'Dispatched',
        'icon': Icons.local_shipping,
        'description': 'Driver is on the way to your location',
      },
      {
        'status': 'ongoing',
        'label': 'Ongoing',
        'icon': Icons.build,
        'description': 'Towing service is in progress',
      },
      {
        'status': 'invoice_generated',
        'label': 'Ready',
        'icon': Icons.emoji_transportation,
        'description':
            'Invoice has been generated, you may come to collect your car',
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.backgroundColor,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Towing Progress',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children:
                    steps.asMap().entries.map((entry) {
                      final index = entry.key;
                      final step = entry.value;
                      final isCompleted = index <= currentIndex;
                      final isCurrent = index == currentIndex;

                      return Expanded(
                        child: Column(
                          children: [
                            // Connection line
                            Container(
                              height: 3,
                              color:
                                  isCompleted
                                      ? Colors.orange
                                      : Colors.grey.shade300,
                            ),
                            const SizedBox(height: 8),

                            // Icon and status
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color:
                                        isCompleted
                                            ? Colors.orange
                                            : Colors.grey.shade300,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    step['icon'] as IconData,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                if (isCurrent)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: AppColors.errorColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),

                            // Label
                            Text(
                              step['label'] as String,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                color:
                                    isCompleted
                                        ? Colors.orange
                                        : Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),

              // Current status description
              if (currentIndex >= 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.secondaryColor,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          steps[currentIndex]['description'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _makeCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  String _getTowingDisplayPrice(Map<String, dynamic> towing) {
    final totalAmount = towing['totalAmount'] as num?;
    final estimatedCost = towing['estimatedCost'] as num?;

    if (totalAmount != null && totalAmount > 0) {
      return 'RM ${totalAmount.toStringAsFixed(2)}';
    } else if (estimatedCost != null && estimatedCost > 0) {
      return 'RM ${estimatedCost.toStringAsFixed(2)}';
    } else {
      return 'RM 0.00';
    }
  }

  Widget _buildPricingCard(Map<String, dynamic> towing) {
    final pricingBreakdown = _safeMapConversion(towing['pricingBreakdown']);

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
            'Pricing Breakdown',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (pricingBreakdown.isNotEmpty) ...[
            _buildPricingRow(
              'Base Fee',
              _formatCurrency(pricingBreakdown['baseFee']),
            ),
            _buildPricingRow(
              'Distance Cost',
              _formatCurrency(pricingBreakdown['distanceCost']),
              description:
                  '${pricingBreakdown['distanceInKm']} km × RM ${pricingBreakdown['perKmRate']}/km',
            ),
            if (pricingBreakdown['luxurySurcharge'] != null)
              _buildPricingRow(
                'Luxury Surcharge',
                _formatCurrency(pricingBreakdown['luxurySurcharge']),
              ),
            const Divider(),
            const SizedBox(height: 8),
            _buildPricingRow(
              'Estimated Cost',
              _formatCurrency(towing['estimatedCost']),
              isTotal: true,
            ),
            if (towing['finalCost'] != null)
              _buildPricingRow(
                'Final Cost',
                _formatCurrency(towing['finalCost']),
                isTotal: true,
              ),
          ],
        ],
      ),
    );
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return 'RM 0.00';
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  Widget _buildPricingRow(
    String label,
    String value, {
    bool isTotal = false,
    String? description,
  }) {
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
                  color:
                      isTotal
                          ? AppColors.primaryColor
                          : AppColors.secondaryColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: isTotal ? 16 : 14,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                  color:
                      isTotal
                          ? AppColors.primaryColor
                          : AppColors.secondaryColor,
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

  Widget _buildTowingPaymentInfoCard(Map<String, dynamic> towing) {
    final paymentStatus = towing['paymentStatus'] as String? ?? 'unpaid';
    final paymentMethod = towing['paymentMethod'] as String? ?? 'N/A';
    final paidAmount = towing['paidAmount'] as double? ?? 0.0;
    final hasPayment = towing['hasPayment'] == true;
    final totalAmount = towing['totalAmount'] as double? ?? 0.0;
    final estimatedCost = towing['estimatedCost'] as double? ?? 0.0;

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
            'Payment Information',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          // Amount Information
          _buildPricingRow('Estimated Cost', _formatCurrency(estimatedCost)),
          if (totalAmount > 0 && totalAmount != estimatedCost)
            _buildPricingRow(
              'Final Cost',
              _formatCurrency(totalAmount),
              isTotal: true,
            ),

          const SizedBox(height: 12),

          // Payment Status
          if (towing['status'] != 'cancelled' &&
              towing['status'] != 'declined') ...[
            Row(
              children: [
                Expanded(
                  child: _buildCompactPaymentDetail(
                    'Status',
                    _getPaymentStatusText(paymentStatus),
                    _getPaymentStatusColor(paymentStatus),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCompactPaymentDetail(
                    'Method',
                    paymentMethod.toUpperCase(),
                    Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            if (hasPayment && paidAmount > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildCompactPaymentDetail(
                      'Paid Amount',
                      'RM${paidAmount.toStringAsFixed(2)}',
                      AppColors.primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> towing) {
    final location = _safeMapConversion(towing['location']);

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
            'Location Details',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (location['customer'] != null) ...[
            const Text(
              'Pickup Location:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (location['customer']['address'] != null) ...[
              _buildDetailRow(
                'Address',
                location['customer']['address']['full'] ?? 'N/A',
              ),
              if (location['customer']['address']['street'] != null)
                _buildDetailRow(
                  'Street',
                  location['customer']['address']['street'],
                ),
              if (location['customer']['address']['city'] != null)
                _buildDetailRow(
                  'City',
                  location['customer']['address']['city'],
                ),
              if (location['customer']['address']['state'] != null)
                _buildDetailRow(
                  'State',
                  location['customer']['address']['state'],
                ),
            ],
          ],
          if (towing['distance'] != null)
            _buildDetailRow(
              'Distance to Service Center',
              '${towing['distance'].toStringAsFixed(1)} km',
            ),
          if (towing['coverageArea'] != null)
            _buildDetailRow('Coverage Area', '${towing['coverageArea']} km'),
        ],
      ),
    );
  }

  Widget _buildServiceDetailsCard(Map<String, dynamic> towing) {
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
            'Service Details',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Towing Type', towing['towingType'] ?? 'N/A'),
          _buildDetailRow(
            'Service Center',
            towing['serviceCenterName'] ?? 'N/A',
          ),
          if (towing['responseTime'] != null)
            _buildDetailRow(
              'Response Time',
              '${towing['responseTime']} minutes',
            ),
          if (towing['estimatedDuration'] != null)
            _buildDetailRow(
              'Estimated Duration',
              '${towing['estimatedDuration']} minutes',
            ),
          if (towing['description']?.isNotEmpty == true)
            _buildDetailRow('Description', towing['description']),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(Map<String, dynamic> towing) {
    final statusHistory = towing['statusHistory'] ?? [];

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
          if (statusHistory.isNotEmpty) ...[
            ...statusHistory
                .map<Widget>(
                  (history) => _buildTimelineItem(
                    history['status'] ?? '',
                    history['timestamp'] ?? Timestamp.now(),
                    history['notes'] ?? '',
                  ),
                )
                .toList(),
          ] else ...[
            Text(
              'No timeline available',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
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
                  _getTowingStatusMessage(status),
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

  void _cancelTowingRequest(Map<String, dynamic> towing) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Request'),
            content: const Text(
              'Are you sure you want to cancel this towing request?',
            ),
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
                        .doc(towing['id'] as String)
                        .update({
                          'status': 'cancelled',
                          'updatedAt': FieldValue.serverTimestamp(),
                          'statusHistory': FieldValue.arrayUnion([
                            {
                              'status': 'cancelled',
                              'timestamp': Timestamp.now(),
                              'updatedBy': 'customer',
                              'notes': 'Request cancelled by customer',
                            },
                          ]),
                        });
                    Navigator.pop(context);
                    Navigator.pop(context); // Close the details sheet
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

  void _showReviewDialog(Map<String, dynamic> item) {
    final isService = item['type'] == 'service';
    final serviceCenterName = item['serviceCenterName'] as String?;
    final hasRating = item['rating'] != null;

    int selectedRating = 0;
    TextEditingController reviewController = TextEditingController();

    if (hasRating) {
      final ratingData = item['rating'] as Map<String, dynamic>;
      selectedRating = (ratingData['stars'] as num?)?.toInt() ?? 0;
      reviewController.text = (ratingData['comment'] as String?) ?? '';
    }

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasRating
                          ? 'Update Your Review'
                          : 'Share Your Experience',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      serviceCenterName ?? 'Service Provider',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Star Rating
                    const Text(
                      'How would you rate your experience?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedRating = index + 1;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: Icon(
                                index < selectedRating
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                                size: 32,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Review Comment
                    const Text(
                      'Share your feedback (optional):',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reviewController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Tell us about your experience...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed:
                        selectedRating > 0
                            ? () => _submitReview(
                              item,
                              selectedRating,
                              reviewController.text.trim(),
                              setState,
                            )
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(hasRating ? 'Update Review' : 'Submit Review'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _submitReview(
    Map<String, dynamic> item,
    int rating,
    String comment,
    StateSetter setState,
  ) async {
    try {
      final isService = item['type'] == 'service';
      final itemId = item['id'] as String?;
      final collectionName = isService ? 'service_bookings' : 'towing_requests';

      String? serviceCenterId;
      String? serviceCenterName;

      if (isService) {
        serviceCenterId = item['serviceCenterId'] as String?;
        serviceCenterName = item['serviceCenterName'] as String?;
      } else {
        serviceCenterId = item['serviceCenterId'] as String?;
        serviceCenterName = item['serviceCenterName'] as String?;
      }

      if (itemId == null) {
        throw Exception('Item ID is null');
      }

      final reviewId = FirebaseFirestore.instance.collection('reviews').doc().id;

      final reviewData = {
        'id': reviewId,
        'serviceCenterId': serviceCenterId,
        'serviceCenterName': serviceCenterName ?? 'Unknown Service Center',
        'userId': widget.userId,
        'userName': widget.userName,
        'userEmail': widget.userEmail,
        'rating': rating,
        'comment': comment.isNotEmpty ? comment : null,
        'type': isService ? 'service' : 'towing',
        'bookingId': itemId,
        'vehicleInfo':
            isService ? (item['vehicle'] ?? {}) : (item['vehicleInfo'] ?? {}),
        'services': isService ? item['services'] : null,
        'packages': isService ? item['packages'] : null,
        'towingType': !isService ? item['towingType'] : null,
        'totalAmount': item['totalAmount'],
        'status': 'approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(reviewId)
          .set(reviewData);

      if (serviceCenterId != null) {
        await FirebaseFirestore.instance
            .collection('service_centers')
            .doc(serviceCenterId)
            .collection('reviews')
            .doc(reviewId)
            .set(reviewData);
      }

      final minimalRatingData = {
        'reviewId': reviewId,
        'stars': rating,
        'comment': comment.isNotEmpty ? comment : null,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': widget.userName,
      };

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(itemId)
          .update({
            'rating': minimalRatingData,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (serviceCenterId != null) {
        await _updateServiceCenterRating(serviceCenterId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your review!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
        _loadServiceHistory(); // Reload to show the updated rating
      }
    } catch (e) {
      debugPrint('Error submitting review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildServiceProgress(Map<String, dynamic> booking) {
    final status = booking['status'] as String? ?? 'unknown';
    final steps = [
      {'status': 'pending', 'label': 'Pending', 'icon': Icons.pending},
      {
        'status': 'confirmed',
        'label': 'Confirmed',
        'icon': Icons.check_circle_outline,
      },
      {'status': 'assigned', 'label': 'Assigned', 'icon': Icons.person_outline},
      {'status': 'in_progress', 'label': 'In Progress', 'icon': Icons.build},
      {
        'status': 'ready_to_collect',
        'label': 'Ready',
        'icon': Icons.emoji_transportation,
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Current Status:',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children:
              steps.asMap().entries.map((entry) {
                final index = entry.key;
                final step = entry.value;
                final isCompleted = index <= currentIndex;
                final isCurrent = index == currentIndex;

                return Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 3,
                              color:
                                  isCompleted
                                      ? AppColors.primaryColor
                                      : Colors.grey.shade300,
                            ),
                          ),
                          if (index < steps.length - 1)
                            const SizedBox(width: 4),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        step['icon'] as IconData,
                        size: 16,
                        color:
                            isCompleted
                                ? AppColors.primaryColor
                                : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              isCompleted
                                  ? AppColors.primaryColor
                                  : Colors.grey.shade500,
                          fontWeight:
                              isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  String _getServiceSummary(Map<String, dynamic> booking) {
    final packages = booking['packages'] as List? ?? [];
    final services = booking['services'] as List? ?? [];
    final selectionType = booking['selectionType'] as String?;

    if (selectionType == 'package' && packages.isNotEmpty) {
      final firstPackage = packages.first as Map<String, dynamic>;
      return 'Package: ${firstPackage['packageName'] ?? 'Service Package'}';
    } else if (selectionType == 'both' &&
        packages.isNotEmpty &&
        services.isNotEmpty) {
      return 'Package + ${services.length} additional service${services.length > 1 ? 's' : ''}';
    } else if (services.isNotEmpty) {
      return '${services.length} service${services.length > 1 ? 's' : ''}';
    } else {
      return 'Service booking';
    }
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

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Waiting for service center confirmation';
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
      case 'declined':
        return 'Booking has been declined by service center';
      default:
        return 'Status unknown';
    }
  }

  String _getTowingStatusMessage(String status) {
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
      case ' invoice_generated':
        return 'Your invoice has generated, and ready to collect your car';
      default:
        return 'Status unknown';
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      //   service booking
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'Service in Progress';
      case 'ready_to_collect':
        return 'Ready to Collect';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'invoice_generated':
        return 'Invoice Generated';
      //   towing request
      case 'accepted':
        return 'Accepted';
      case 'dispatched':
        return 'On the way';
      default:
        return status;
    }
  }

  String _getPaymentStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Awaiting Payment';
      case 'unpaid':
        return 'Awaiting Payment';
      case 'paid':
        return 'Payment Completed';
      case 'failed':
        return 'Payment Failed';
      case 'refunded':
        return 'Payment Refunded';
      case 'partially_paid':
        return 'Partially Paid';
      default:
        return status;
    }
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'unpaid':
        return Colors.red;
      case 'failed':
        return Colors.red;
      case 'refunded':
        return Colors.orange;
      case 'partially_paid':
        return Colors.amber;
      case 'pending':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
      case 'assigned':
      case 'dispatched':
        return Colors.blue;
      case 'in_progress':
        return Colors.indigo;
      case 'invoice_generated':
      case 'ready_to_collect':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'declined':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
