import 'package:automate_application/pages/chat/customer_support_chat_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:automate_application/pages/service_history/service_invoice_page.dart';

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

  // Enhanced filtering options
  String _selectedServiceType = 'all'; // 'all', 'service', 'towing'
  String _selectedVehicle = 'all';
  String _selectedTimeFilter = 'all'; // 'all', 'today', 'week', 'month'

  // Vehicle list for filtering
  List<String> _userVehicles = [];
  Map<String, Map<String, dynamic>> _vehicleDetails = {};

  // App Colors
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

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

      // --- Service Bookings ---
      final bookingsSnapshot =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .where('userId', isEqualTo: widget.userId)
              .orderBy('createdAt', descending: true)
              .get();

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final vehicle = data['vehicle'] as Map<String, dynamic>? ?? {};

        history.add({
          'id': doc.id,
          'type': 'service',
          'serviceCenterId': data['serviceCenterId'],
          'serviceCenterName': await _getServiceCenterName(
            data['serviceCenterId'],
          ),
          'invoiceId': data['invoiceId'],
          'estimatedDuration': data['estimatedDuration'],
          'status': data['status'] ?? 'unknown',
          'scheduledDate': data['scheduledDate'] as Timestamp?,
          'scheduledTime': data['scheduledTime'],
          'totalAmount': _calculateTotalAmount(data),
          'displayPrice': _getDisplayPrice(data),
          'services': data['services'] ?? [],
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
          'paymentStatus': data['payment']?['paymentStatus'] ?? 'pending',
          'cancellation': data['cancellation'],
          'rating': data['rating'],
          'technician': data['technicianId'],
          'bay': data['bayId'],
        });
      }

      // --- Towing Requests ---
      final towingSnapshot =
          await FirebaseFirestore.instance
              .collection('towing_requests')
              .where('userId', isEqualTo: widget.userId)
              .orderBy('createdAt', descending: true)
              .get();

      for (var doc in towingSnapshot.docs) {
        final data = doc.data();
        final vehicleInfo = _safeMapConversion(data['vehicleInfo']);
        final timing = _safeMapConversion(data['timing']);
        final payment = _safeMapConversion(data['payment']);

        history.add({
          'id': doc.id,
          'type': 'towing',
          'status': data['status'] ?? 'unknown',
          'serviceCenterId': data['serviceCenterId'],
          'serviceCenterName':
              data['serviceCenterName'] ?? 'Unknown Service Center',
          'towingType': data['towingType'] ?? 'Unknown',
          'location': data['location'] ?? {},
          'destination': data['destination'] ?? {},
          'vehicleInfo': vehicleInfo,
          'vehiclePlate': vehicleInfo['plateNumber'] ?? 'Unknown',
          'driverInfo':
              data['driverInfo'] != null
                  ? _safeMapConversion(data['driverInfo'])
                  : null,
          'distance': data['distance']?.toDouble(),
          'estimatedCost': (data['estimatedCost'] ?? 0).toDouble(),
          'totalAmount':
              (payment['totalAmount'] ?? data['estimatedCost'] ?? 0).toDouble(),
          'description': data['description'] ?? '',
          'contactNumber': data['contactNumber'] ?? '',
          'createdAt': data['createdAt'] as Timestamp?,
          'updatedAt': data['updatedAt'] as Timestamp?,
          'requestedAt': timing['requestedAt'] as Timestamp?,
          'assignedAt': timing['assignedAt'] as Timestamp?,
          'completedAt': timing['completedAt'] as Timestamp?,
          'paymentStatus': payment['paymentStatus'] ?? 'pending',
          'cancellation': data['cancellation'],
          'rating': data['rating'],
        });
      }

      // Sort by creation date
      history.sort((a, b) {
        final aDate = a['createdAt'] as Timestamp?;
        final bDate = b['createdAt'] as Timestamp?;
        if (aDate == null || bDate == null) return 0;
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
    }
  }

  double _calculateTotalAmount(Map<String, dynamic> data) {
    try {
      if (data['totalAmount'] != null && data['totalAmount'] > 0) {
        return (data['totalAmount'] as num).toDouble();
      }

      if (data['totalFixedPrice'] != null && data['totalFixedPrice'] > 0) {
        return (data['totalFixedPrice'] as num).toDouble();
      }

      // Calculate from packages and services
      double total = 0;
      final packages = _getAllPackages(data);
      final services = data['services'] as List? ?? [];

      for (var pkg in packages) {
        if (pkg['fixedPrice'] != null && pkg['fixedPrice'] > 0) {
          total += (pkg['fixedPrice'] as num).toDouble();
        }
      }

      for (var service in services) {
        if (service['serviceTotal'] != null && service['serviceTotal'] > 0) {
          total += (service['serviceTotal'] as num).toDouble();
        } else if (service['totalFixedPrice'] != null &&
            service['totalFixedPrice'] > 0) {
          total += (service['totalFixedPrice'] as num).toDouble();
        } else {
          final labour = (service['labourPrice'] as num?)?.toDouble() ?? 0;
          final parts = (service['partPrice'] as num?)?.toDouble() ?? 0;
          total += labour + parts;
        }
      }

      return total;
    } catch (e) {
      return 0.0;
    }
  }

  String _getDisplayPrice(Map<String, dynamic> data) {
    final totalRangePrice = data['totalRangePrice'] as String?;
    final totalAmount = _calculateTotalAmount(data);

    if (totalRangePrice != null && totalRangePrice.isNotEmpty) {
      return totalRangePrice;
    } else if (totalAmount > 0) {
      return 'RM${totalAmount.toStringAsFixed(2)}';
    } else {
      return 'Price upon inspection';
    }
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
      case 0: // All
        return filtered;
      case 1: // Active (pending, confirmed, assigned, in_progress)
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
      case 2: // Ready (ready_to_collect)
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
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Enhanced Filter Section
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
      backgroundColor: cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: secondaryColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Service History',
        style: TextStyle(
          color: secondaryColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.refresh, color: secondaryColor, size: 20),
          ),
          onPressed: _loadServiceHistory,
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: primaryColor,
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
      color: cardColor,
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
          CircularProgressIndicator(color: primaryColor),
          SizedBox(height: 16),
          Text(
            'Loading service history...',
            style: TextStyle(
              color: secondaryColor,
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
                backgroundColor: primaryColor,
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
                backgroundColor: primaryColor,
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
      color: primaryColor,
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
        color: cardColor,
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
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'SERVICE',
                    style: TextStyle(
                      color: primaryColor,
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
                // Service Center - FIXED: Proper null handling
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
                          color: secondaryColor,
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
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            (booking['displayPrice'] as String?) ??
                                'RM${((booking['totalAmount'] as num?) ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),

                      if (booking['paymentStatus'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Payment: ${_getPaymentStatusText(booking['paymentStatus'] as String? ?? 'pending')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPaymentStatusColor(
                              booking['paymentStatus'] as String? ?? 'pending',
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
                Row(
                  children: [
                    // Review button for completed services
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

                    // Details button
                    TextButton(
                      onPressed: () => _showServiceDetails(booking),
                      style: TextButton.styleFrom(
                        foregroundColor: primaryColor,
                        backgroundColor: primaryColor.withOpacity(0.1),
                      ),
                      child: const Text('View Details'),
                    ),
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
                    color: cardColor,
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
                                      color: secondaryColor,
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
                                          color: primaryColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'SERVICE',
                                          style: TextStyle(
                                            color: primaryColor,
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
                              // Quick Info Cards
                              _buildQuickInfoSection(booking),

                              const SizedBox(height: 20),

                              // Service Center Information
                              _buildServiceCenterSection(booking),

                              const SizedBox(height: 20),

                              // Vehicle Information
                              _buildVehicleSection(booking),

                              const SizedBox(height: 20),

                              // Services & Packages
                              _buildServicesSection(
                                booking,
                                packagesList,
                                servicesList,
                                selectionType,
                              ),

                              const SizedBox(height: 20),

                              // Payment Information
                              _buildPaymentSection(booking),

                              const SizedBox(height: 20),

                              // Rating Section
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
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
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

  // Helper Methods for Service Details
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
        'status': 'ready_to_collect',
        'label': 'Ready',
        'icon': Icons.emoji_transportation,
        'description': 'Ready for collection',
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service Progress',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
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
                              isCompleted ? primaryColor : Colors.grey.shade300,
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
                                        ? primaryColor
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
                                    ? primaryColor
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
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue.shade600,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      steps[currentIndex]['description'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
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
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business, size: 20, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Service Center',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
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
        color: primaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_car, size: 20, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'Vehicle Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildVehicleDetail('Make', vehicle['make'] as String?),
              _buildVehicleDetail('Model', vehicle['model'] as String?),
              _buildVehicleDetail('Year', vehicle['year']?.toString()),
              _buildVehicleDetail('Plate', vehicle['plateNumber'] as String?),
              _buildVehicleDetail('Fuel Type', vehicle['fuelType'] as String?),
              _buildVehicleDetail(
                'Size Class',
                vehicle['sizeClass'] as String?,
              ),
              _buildVehicleDetail(
                'Displacement',
                vehicle['displacement'] as String?,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetail(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value ?? 'N/A',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: secondaryColor,
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
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 12),

        // Packages
        if (hasPackages) ...[
          ...packagesList
              .map(
                (package) => _buildPackageCard(package as Map<String, dynamic>),
              )
              .toList(),
          const SizedBox(height: 16),
        ],

        // Individual Services
        if (hasServices) ...[
          if (hasPackages)
            Text(
              'Additional Services',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: secondaryColor,
              ),
            ),
          const SizedBox(height: 8),
          ...servicesList
              .map(
                (service) =>
                    _buildServiceItemCard(service as Map<String, dynamic>),
              )
              .toList(),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: secondaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: secondaryColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.inventory_2, size: 20, color: secondaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (package['packageName'] as String?) ?? 'Service Package',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: secondaryColor,
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

          const SizedBox(height: 12),

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
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Package Price:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  _getPackagePrice(package),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),

          if (package['estimatedDuration'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Estimated Duration: ${package['estimatedDuration']} minutes',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.build_circle_outlined, size: 16, color: primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (service['serviceName'] as String?) ?? 'Service',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: secondaryColor,
                  ),
                ),
                if (service['description'] != null &&
                    (service['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    service['description'] as String,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _getServicePrice(service),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSection(Map<String, dynamic> booking) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Payment Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDetailItem(
            'Total Amount',
            (booking['displayPrice'] as String?) ??
                'RM${((booking['totalAmount'] as num?) ?? 0).toStringAsFixed(2)}',
          ),
          _buildDetailItem(
            'Payment Status',
            _getPaymentStatusText(
              booking['paymentStatus'] as String? ?? 'pending',
            ),
          ),
          _buildDetailItem(
            'Payment Method',
            ((booking['payment'] as Map<String, dynamic>?)?['method']
                        as String? ??
                    'cash')
                .toUpperCase(),
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
                  color: secondaryColor,
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
                color: secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for pricing
  String _getPackagePrice(Map<String, dynamic> package) {
    if (package['rangePrice'] != null &&
        (package['rangePrice'] as String).isNotEmpty) {
      return package['rangePrice'] as String;
    } else if (package['fixedPrice'] != null &&
        (package['fixedPrice'] as num) > 0) {
      return 'RM${(package['fixedPrice'] as num).toStringAsFixed(2)}';
    } else {
      return 'Price upon inspection';
    }
  }

  String _getServicePrice(Map<String, dynamic> service) {
    if (service['totalRangePrice'] != null &&
        (service['totalRangePrice'] as String).isNotEmpty) {
      return service['totalRangePrice'] as String;
    } else if (service['partPrice'] != null && service['labourPrice'] != null) {
      final total =
          ((service['partPrice'] as num?) ?? 0) +
          ((service['labourPrice'] as num?) ?? 0);
      return 'RM${total.toStringAsFixed(2)}';
    } else if (service['partPriceMin'] != null ||
        service['labourPriceMin'] != null) {
      final min =
          ((service['partPriceMin'] as num?) ?? 0) +
          ((service['labourPriceMin'] as num?) ?? 0);
      final max =
          ((service['partPriceMax'] as num?) ?? 0) +
          ((service['labourPriceMax'] as num?) ?? 0);
      return 'RM${min.toStringAsFixed(2)} - RM${max.toStringAsFixed(2)}';
    } else {
      return 'Price upon inspection';
    }
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
    final status = towing['status'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final createdAt = towing['createdAt'] as Timestamp?;
    final isCompleted = status.toLowerCase() == 'completed';
    final hasRating =
        towing['rating'] != null &&
        (towing['rating'] as Map<String, dynamic>).isNotEmpty &&
        (towing['rating']?['stars'] != null);

    Map<String, dynamic> _safeMapConversion(dynamic value) {
      if (value == null) return <String, dynamic>{};
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return <String, dynamic>{};
    }

    final vehicleInfo = _safeMapConversion(towing['vehicleInfo']);
    final location = _safeMapConversion(towing['location']);
    final destination = _safeMapConversion(towing['destination']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
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
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Towing Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'TOWING',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (createdAt != null)
                  Text(
                    formatDate(createdAt),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        (towing['towingType'] as String?) ?? 'Towing Service',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: secondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Vehicle Details
                if (vehicleInfo.isNotEmpty) ...[
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
                          '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''} ${vehicleInfo['plateNumber'] ?? ''} (${vehicleInfo['year'] ?? ''})',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Pickup Location
                if (location['address'] != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'From: ${location['address']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Destination
                if (destination['serviceCenterName'] != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.flag, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'To: ${destination['serviceCenterName']}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Distance
                if (towing['distance'] != null) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.straighten,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Distance: ${(towing['distance'] as num).toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // Driver Info
                if (towing['driverInfo'] != null) ...[
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(
                        'Driver: ${_safeMapConversion(towing['driverInfo'])['name'] ?? 'Assigned'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),

          // Footer
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
                if (isCompleted && !hasRating)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    child: ElevatedButton(
                      onPressed: () => _showReviewDialog(towing),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Review',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => _showTowingDetails(towing),
                  child: const Text(
                    'View Details',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTowingDetails(Map<String, dynamic> towing) {
    Map<String, dynamic> _safeMapConversion(dynamic value) {
      if (value == null) return <String, dynamic>{};
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return <String, dynamic>{};
    }

    final vehicleInfo = _safeMapConversion(towing['vehicleInfo']);
    final location = _safeMapConversion(towing['location']);
    final destination = _safeMapConversion(towing['destination']);
    final driverInfo =
        towing['driverInfo'] != null
            ? _safeMapConversion(towing['driverInfo'])
            : null;
    final status = towing['status'] as String? ?? 'unknown';
    final isActive = [
      'pending',
      'confirmed',
      'assigned',
      'dispatched',
      'in_progress',
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
                    color: cardColor,
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
                                      color: secondaryColor,
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
                      if (isActive) _buildTowingProgressIndicator(towing),

                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Quick Info Cards
                              _buildTowingQuickInfoSection(towing),

                              const SizedBox(height: 20),

                              // Request Information
                              _buildRequestInfoSection(towing),

                              const SizedBox(height: 20),

                              // Vehicle Information
                              if (vehicleInfo.isNotEmpty)
                                _buildTowingVehicleSection(vehicleInfo),

                              const SizedBox(height: 20),

                              // Location Information
                              _buildLocationSection(location, destination),

                              const SizedBox(height: 20),

                              // Driver Information
                              if (driverInfo != null)
                                _buildDriverSection(driverInfo),

                              const SizedBox(height: 20),

                              // Timeline
                              _buildTowingTimelineSection(towing),

                              const SizedBox(height: 20),

                              // Description
                              if (towing['description'] != null &&
                                  (towing['description'] as String).isNotEmpty)
                                _buildDescriptionSection(towing),

                              const SizedBox(height: 20),

                              // Payment Information
                              _buildTowingPaymentSection(towing),

                              const SizedBox(height: 20),

                              // Cancellation Details
                              if (towing['cancellation'] != null)
                                _buildCancellationSection(towing),

                              const SizedBox(height: 20),

                              // Rating Section
                              if (isCompleted)
                                _buildTowingRatingSection(towing),

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
                            // Review Button for completed towing without rating
                            if (isCompleted && !hasRating)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showReviewDialog(towing),
                                  icon: const Icon(Icons.star, size: 18),
                                  label: const Text('Add Review'),
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
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  // Helper Methods for Towing Details
  Widget _buildTowingProgressIndicator(Map<String, dynamic> towing) {
    final status = towing['status'] as String? ?? 'unknown';
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
        'description': 'Request confirmed',
      },
      {
        'status': 'assigned',
        'label': 'Assigned',
        'icon': Icons.person_outline,
        'description': 'Driver assigned',
      },
      {
        'status': 'dispatched',
        'label': 'Dispatched',
        'icon': Icons.directions_car,
        'description': 'Driver on the way',
      },
      {
        'status': 'in_progress',
        'label': 'In Progress',
        'icon': Icons.build,
        'description': 'Towing in progress',
      },
      {
        'status': 'completed',
        'label': 'Completed',
        'icon': Icons.check_circle,
        'description': 'Towing completed',
      },
    ];

    final currentIndex = steps.indexWhere((step) => step['status'] == status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(bottom: BorderSide(color: Colors.orange.shade100)),
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
          const SizedBox(height: 12),

          // Simplified progress for mobile
          Row(
            children: [
              Icon(Icons.local_shipping, size: 20, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  steps[currentIndex >= 0 ? currentIndex : 0]['description']
                      as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: currentIndex >= 0 ? (currentIndex + 1) / steps.length : 0,
            backgroundColor: Colors.grey.shade300,
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildTowingQuickInfoSection(Map<String, dynamic> towing) {
    return Row(
      children: [
        // Request ID
        Expanded(
          child: _buildTowingInfoCard(
            icon: Icons.confirmation_number,
            title: 'Request ID',
            value: (towing['id']?.toString().substring(0, 8)) ?? 'N/A',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),

        // Distance
        if (towing['distance'] != null)
          Expanded(
            child: _buildTowingInfoCard(
              icon: Icons.space_dashboard,
              title: 'Distance',
              value: '${(towing['distance'] as num).toStringAsFixed(1)} km',
              color: Colors.green,
            ),
          ),
      ],
    );
  }

  Widget _buildTowingInfoCard({
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

  Widget _buildRequestInfoSection(Map<String, dynamic> towing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping, size: 20, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Request Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTowingDetailItem(
            'Towing Type',
            (towing['towingType'] as String?) ?? 'Standard',
          ),
          _buildTowingDetailItem(
            'Contact Number',
            (towing['contactNumber'] as String?) ?? 'N/A',
          ),
          _buildTowingDetailItem(
            'Payment Status',
            _getPaymentStatusText(
              towing['paymentStatus'] as String? ?? 'pending',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowingVehicleSection(Map<String, dynamic> vehicleInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_car, size: 20, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Vehicle Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildVehicleDetailCard('Make', vehicleInfo['make'] as String?),
              _buildVehicleDetailCard('Model', vehicleInfo['model'] as String?),
              _buildVehicleDetailCard('Year', vehicleInfo['year']?.toString()),
              _buildVehicleDetailCard(
                'Plate',
                vehicleInfo['plateNumber'] as String?,
              ),
              if (vehicleInfo['sizeClass'] != null)
                _buildVehicleDetailCard(
                  'Size Class',
                  vehicleInfo['sizeClass'] as String?,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetailCard(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value ?? 'N/A',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(
    Map<String, dynamic> location,
    Map<String, dynamic> destination,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on, size: 20, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'Location Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pickup Location
          if (location.isNotEmpty) ...[
            _buildLocationCard(
              title: 'Pickup Location',
              address: location['address']?.toString(),
              icon: Icons.my_location,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
          ],

          // Destination
          if (destination.isNotEmpty) ...[
            _buildLocationCard(
              title: 'Destination',
              address: destination['address']?.toString(),
              serviceCenter: destination['serviceCenterName']?.toString(),
              icon: Icons.flag,
              color: Colors.red,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationCard({
    required String title,
    required String? address,
    required IconData icon,
    required Color color,
    String? serviceCenter,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (serviceCenter != null) ...[
            Text(
              serviceCenter,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: secondaryColor,
              ),
            ),
            const SizedBox(height: 4),
          ],
          if (address != null && address.isNotEmpty)
            Text(
              address,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverSection(Map<String, dynamic> driverInfo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, size: 20, color: Colors.teal),
              const SizedBox(width: 8),
              Text(
                'Driver Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildDriverDetailCard('Name', driverInfo['name'] as String?),
              _buildDriverDetailCard('Phone', driverInfo['phoneNo'] as String?),
              if (driverInfo['make'] != null && driverInfo['model'] != null)
                _buildDriverDetailCard(
                  'Tow Vehicle',
                  '${driverInfo['make']} ${driverInfo['model']}',
                ),
              if (driverInfo['carPlate'] != null)
                _buildDriverDetailCard(
                  'Plate',
                  driverInfo['carPlate'] as String?,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverDetailCard(String label, String? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value ?? 'N/A',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.teal.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowingTimelineSection(Map<String, dynamic> towing) {
    final hasTimeline =
        towing['requestedAt'] != null ||
        towing['assignedAt'] != null ||
        towing['completedAt'] != null;

    if (!hasTimeline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, size: 20, color: Colors.grey.shade700),
              const SizedBox(width: 8),
              Text(
                'Timeline',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: [
              if (towing['requestedAt'] != null)
                _buildTimelineItem(
                  'Requested',
                  towing['requestedAt'] as Timestamp?,
                  Icons.schedule,
                ),
              if (towing['assignedAt'] != null)
                _buildTimelineItem(
                  'Assigned',
                  towing['assignedAt'] as Timestamp?,
                  Icons.person,
                ),
              if (towing['completedAt'] != null)
                _buildTimelineItem(
                  'Completed',
                  towing['completedAt'] as Timestamp?,
                  Icons.check_circle,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(String event, Timestamp? timestamp, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              event,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            timestamp != null ? formatDateTime(timestamp) : 'Pending',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(Map<String, dynamic> towing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description, size: 20, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            towing['description'] as String,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildTowingPaymentSection(Map<String, dynamic> towing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Payment Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: secondaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTowingDetailItem(
            'Total Amount',
            'RM${((towing['totalAmount'] as num?) ?? 0).toStringAsFixed(2)}',
          ),
          _buildTowingDetailItem(
            'Estimated Cost',
            'RM${((towing['estimatedCost'] as num?) ?? 0).toStringAsFixed(2)}',
          ),
          _buildTowingDetailItem(
            'Payment Status',
            _getPaymentStatusText(
              towing['paymentStatus'] as String? ?? 'pending',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancellationSection(Map<String, dynamic> towing) {
    final cancellation = _safeMapConversion(towing['cancellation']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cancel, size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text(
                'Cancellation Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTowingDetailItem(
            'Reason',
            (cancellation['reason'] as String?) ?? 'Not specified',
          ),
          _buildTowingDetailItem(
            'Cancelled By',
            (cancellation['cancelledBy'] as String?) ?? 'Unknown',
          ),
          if (cancellation['cancelledAt'] != null)
            _buildTowingDetailItem(
              'Cancelled At',
              formatDateTime(cancellation['cancelledAt'] as Timestamp?),
            ),
        ],
      ),
    );
  }

  Widget _buildTowingRatingSection(Map<String, dynamic> towing) {
    final rating = towing['rating'] as Map<String, dynamic>?;
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
                  color: secondaryColor,
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
              'How was your towing experience?',
              style: TextStyle(color: Colors.amber.shade700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _showReviewDialog(towing),
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

  Widget _buildTowingDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: secondaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReviewDialog(Map<String, dynamic> item) {
    final isService = item['type'] == 'service';
    final itemId = item['id'] as String?;
    final serviceCenterId =
        isService
            ? item['serviceCenterId'] as String?
            : item['serviceCenterId'] as String?;
    final serviceCenterName = item['serviceCenterName'] as String?;

    // Check if already has a review
    final hasRating = item['rating'] != null;

    int selectedRating = 0;
    TextEditingController reviewController = TextEditingController();

    // If already has a review, pre-fill the data
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
                title: Text(
                  hasRating
                      ? 'Update Your ${isService ? 'Service' : 'Towing'} Review'
                      : 'Rate Your ${isService ? 'Service' : 'Towing'} Experience',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: secondaryColor,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceCenterName ?? 'Service Center',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Star Rating
                    const Text(
                      'How would you rate your experience?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
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
                              size: 28,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),

                    // Review Comment
                    const Text(
                      'Additional comments (optional):',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reviewController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Share your experience...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(10),
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
                      backgroundColor: primaryColor,
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

      // Get service center info
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

      // Create review ID
      final reviewId =
          FirebaseFirestore.instance.collection('reviews').doc().id;

      // Prepare complete review data
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

      // 1. Save to main reviews collection
      await FirebaseFirestore.instance
          .collection('reviews')
          .doc(reviewId)
          .set(reviewData);

      // 2. Save to service center's reviews subcollection
      if (serviceCenterId != null) {
        await FirebaseFirestore.instance
            .collection('service_centers')
            .doc(serviceCenterId)
            .collection('reviews')
            .doc(reviewId)
            .set(reviewData);
      }

      // 3. Update the original booking with minimal rating data
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

      // 4. Update service center's average rating
      if (serviceCenterId != null) {
        await _updateServiceCenterRating(serviceCenterId);
      }

      // Show success and reload
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
                                      ? primaryColor
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
                            isCompleted ? primaryColor : Colors.grey.shade400,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              isCompleted ? primaryColor : Colors.grey.shade500,
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

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'confirmed':
        return 'Confirmed';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'ready_to_collect':
        return 'Ready to Collect';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String _getPaymentStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'paid':
        return 'Paid';
      case 'failed':
        return 'Failed';
      case 'refunded':
        return 'Refunded';
      default:
        return status;
    }
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'refunded':
        return Colors.orange;
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
        return Colors.blue;
      case 'in_progress':
        return Colors.indigo;
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
