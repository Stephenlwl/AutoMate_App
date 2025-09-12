import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:encrypt/encrypt.dart';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';

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

class BookServicePage extends StatefulWidget {
  final String userId;
  final ServiceCenter serviceCenter;

  const BookServicePage({
    super.key,
    required this.userId,
    required this.serviceCenter,
  });

  @override
  State<BookServicePage> createState() => _BookServicePageState();
}

class _BookServicePageState extends State<BookServicePage> {
  final PageController _pageController = PageController();
  int currentStep = 0;

  // Form data
  String? selectedVehicleId;
  Map<String, dynamic>? selectedVehicle;
  List<ServiceCenterServiceOffer> selectedServices = [];
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  String urgencyLevel = 'normal';
  String additionalNotes = '';

  List<Map<String, dynamic>> userVehicles = [];
  List<ServiceCenterServiceOffer> availableServices = [];
  List<Map<String, dynamic>> serviceCategories = [];
  List<String> availableTimeSlots = [];
  bool loading = false;
  bool servicesLoading = false;
  double totalFixedPrice = 0.0;
  String totalRangePrice = '';
  bool isServiceCenterOpen = false;

  // Encryption key
  static const String _encryptionKey = 'AUTO_MATE_SECRET_KEY_256';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadServiceCategories();
    _checkServiceCenterStatus();
    _generateTimeSlots();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final vehicles = List<Map<String, dynamic>>.from(
            data['vehicles'] ?? []);
        setState(() {
          userVehicles = vehicles;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadServiceCategories() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('services_categories')
          .where('active', isEqualTo: true)
          .get();

      setState(() {
        serviceCategories = query.docs
            .map((doc) => {
          'id': doc.id,
          'name': doc['name'] ?? '',
          'description': doc['description'] ?? '',
        })
            .toList();
      });
    } catch (e) {
      debugPrint('Error loading service categories: $e');
    }
  }

  void _checkServiceCenterStatus() {
    final now = DateTime.now();
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final currentDay = dayNames[now.weekday - 1];

    final todayHours = widget.serviceCenter.operatingHours
        .firstWhere((hours) => hours['day'] == currentDay, orElse: () => {});

    if (todayHours.isNotEmpty) {
      final isClosed = todayHours['isClosed'] == true;
      if (!isClosed) {
        final openTime = _parseTimeString(todayHours['open'] ?? '09:00');
        final closeTime = _parseTimeString(todayHours['close'] ?? '18:00');
        final currentTime = TimeOfDay.now();

        setState(() {
          isServiceCenterOpen = _isTimeInRange(currentTime, openTime, closeTime);
        });
      }
    }
  }

  TimeOfDay _parseTimeString(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  bool _isTimeInRange(TimeOfDay current, TimeOfDay open, TimeOfDay close) {
    final currentMinutes = current.hour * 60 + current.minute;
    final openMinutes = open.hour * 60 + open.minute;
    final closeMinutes = close.hour * 60 + close.minute;

    return currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
  }

  Future<void> _loadServicesForVehicle() async {
    if (selectedVehicle == null) return;

    setState(() => servicesLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('service_center_services_offer')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('active', isEqualTo: true)
          .get();

      final allOffers = query.docs
          .map((doc) =>
          ServiceCenterServiceOffer.fromFirestore(doc.id, doc.data()))
          .toList();

      // Filter offers that match the selected vehicle
      final vehicleMake = selectedVehicle!['brand'] ??
          selectedVehicle!['make'] ?? '';
      final vehicleModel = selectedVehicle!['model'] ?? '';
      final vehicleYear = selectedVehicle!['year']?.toString() ?? '';

      final matchingOffers = allOffers.where((offer) {
        // Check if offer supports this vehicle make
        bool makeMatches = offer.makes.isEmpty ||
            offer.makes.any((make) =>
                make.toLowerCase().contains(vehicleMake.toLowerCase()));

        // Check if offer supports this vehicle model
        bool modelMatches = offer.models.isEmpty ||
            offer.models[vehicleMake]?.any((model) =>
                model.toLowerCase().contains(vehicleModel.toLowerCase())) ==
                true;

        // Check if offer supports this vehicle year
        bool yearMatches = offer.years.isEmpty ||
            offer.years[vehicleMake]?.contains(vehicleYear) == true;

        return makeMatches && (modelMatches || offer.models.isEmpty) && (yearMatches || offer.years.isEmpty);
      }).toList();

      // Get service names and categories
      if (matchingOffers.isNotEmpty) {
        final serviceIds = matchingOffers
            .map((o) => o.serviceId)
            .toSet()
            .toList();
        final serviceQuery = await FirebaseFirestore.instance
            .collection('services')
            .where(FieldPath.documentId, whereIn: serviceIds)
            .get();

        final serviceMap = {
          for (var doc in serviceQuery.docs) doc.id: {
            'name': doc['name'] ?? '',
            'categoryId': doc['categoryId'] ?? '',
          },
        };

        for (var offer in matchingOffers) {
          final serviceData = serviceMap[offer.serviceId];
          offer.serviceName = serviceData?['name'];
        }
      }

      setState(() {
        availableServices = matchingOffers;
        servicesLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading services: $e');
      setState(() => servicesLoading = false);
    }
  }

  void _calculateTotalPrice() {
    if (selectedServices.isEmpty) {
      setState(() {
        totalFixedPrice = 0.0;
        totalRangePrice = '';
      });
      return;
    }

    double fixedTotal = 0.0;
    double minTotal = 0.0;
    double maxTotal = 0.0;
    bool hasFixedPricing = false;
    bool hasRangePricing = false;

    for (var service in selectedServices) {
      bool hasFixedPartPrice = service.partPrice > 0;
      bool hasFixedLabourPrice = service.labourPrice > 0;

      if (hasFixedPartPrice && hasFixedLabourPrice) {
        hasFixedPricing = true;
        fixedTotal += service.partPrice + service.labourPrice;
      } else {
        hasRangePricing = true;
        minTotal += (service.partPriceMin + service.labourPriceMin);
        maxTotal += (service.partPriceMax + service.labourPriceMax);
      }
    }

    setState(() {
      if (hasFixedPricing && hasRangePricing) {
        // Mixed pricing
        totalFixedPrice = fixedTotal;
        totalRangePrice =
        'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal +
            maxTotal).toStringAsFixed(2)}';
      } else if (hasRangePricing) {
        // Only range pricing
        totalFixedPrice = 0.0;
        totalRangePrice =
        'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
      } else {
        // Only fixed pricing
        totalFixedPrice = fixedTotal;
        totalRangePrice = '';
      }
    });
  }

  void _generateTimeSlots() {
    availableTimeSlots.clear();
    final startHour = 9;
    final endHour = 17;

    for (int hour = startHour; hour < endHour; hour++) {
      availableTimeSlots.add('${hour.toString().padLeft(2, '0')}:00');
      availableTimeSlots.add('${hour.toString().padLeft(2, '0')}:30');
    }
  }

  void _nextStep() {
    if (currentStep < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => currentStep++);
    }
  }

  void _previousStep() {
    if (currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => currentStep--);
    }
  }

  bool _canProceed() {
    switch (currentStep) {
      case 0: return selectedVehicle != null;
      case 1: return selectedServices.isNotEmpty;
      case 2: return selectedDate != null && selectedTime != null;
      case 3: return true;
      default: return false;
    }
  }

  Future<void> _confirmBooking() async {
    if (!_canProceed()) return;

    setState(() => loading = true);

    try {
      final bookingData = {
        'userId': widget.userId,
        'serviceCenterId': widget.serviceCenter.id,
        'vehicleId': selectedVehicleId,
        'vehicle': selectedVehicle,
        'services': selectedServices.map((s) => {
          'serviceId': s.serviceId,
          'serviceName': s.serviceName,
          'offerId': s.id,
          'duration': s.duration,
          'partPrice': s.partPrice,
          'labourPrice': s.labourPrice,
          'partPriceMin': s.partPriceMin,
          'partPriceMax': s.partPriceMax,
          'labourPriceMin': s.labourPriceMin,
          'labourPriceMax': s.labourPriceMax,
        }).toList(),
        'scheduledDate': selectedDate,
        'scheduledTime': '${selectedTime!.hour}:${selectedTime!.minute.toString().padLeft(2, '0')}',
        'urgencyLevel': urgencyLevel,
        'additionalNotes': additionalNotes,
        'totalFixedPrice': totalFixedPrice,
        'totalRangePrice': totalRangePrice,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('service_bookings')
          .add(bookingData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Service booking confirmed successfully!'),
            backgroundColor: AppColors.successColor,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book service: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Book Service',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Service Center Status
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isServiceCenterOpen
                        ? AppColors.successColor.withOpacity(0.2)
                        : AppColors.errorColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isServiceCenterOpen
                          ? AppColors.successColor
                          : AppColors.errorColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isServiceCenterOpen ? Icons.access_time : Icons.schedule,
                        size: 16,
                        color: isServiceCenterOpen
                            ? AppColors.successColor
                            : AppColors.errorColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isServiceCenterOpen ? 'Open Now' : 'Closed',
                        style: TextStyle(
                          color: isServiceCenterOpen
                              ? AppColors.successColor
                              : AppColors.errorColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: List.generate(4, (index) =>
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                          height: 4,
                          decoration: BoxDecoration(
                            color: index <= currentStep
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => currentStep = index);
              },
              children: [
                _buildVehicleSelection(),
                _buildServiceSelection(),
                _buildDateTimeSelection(),
                _buildConfirmation(),
              ],
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildVehicleSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Your Vehicle',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which vehicle needs service at ${widget.serviceCenter.name}',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),

          if (userVehicles.isEmpty)
            _buildEmptyVehicleState()
          else
            ...userVehicles.map((vehicle) {
              final isSelected = selectedVehicleId == vehicle['vehicle_id'];

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  elevation: isSelected ? 8 : 2,
                  shadowColor: isSelected
                      ? AppColors.primaryColor.withOpacity(0.3)
                      : Colors.black.withOpacity(0.1),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        selectedVehicleId = vehicle['vehicle_id'];
                        selectedVehicle = vehicle;
                        selectedServices.clear();
                        _calculateTotalPrice();
                      });
                      _loadServicesForVehicle();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryColor
                              : AppColors.borderColor,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: (isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.textMuted)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.directions_car,
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.textMuted,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${vehicle['brand'] ?? vehicle['make'] ?? 'Unknown'} ${vehicle['model'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? AppColors.primaryColor
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _buildVehicleInfo(
                                      Icons.calendar_today_outlined,
                                      'Year: ${vehicle['year'] ?? 'N/A'}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _buildVehicleInfo(
                                      Icons.confirmation_number_outlined,
                                      vehicle['plate_number'] ?? 'N/A',
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.surfaceColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isSelected
                                  ? Icons.check
                                  : Icons.radio_button_unchecked,
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textMuted,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildVehicleInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyVehicleState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No vehicles found',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a vehicle to your profile to book services',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSelection() {
    // Group services by category
    Map<String, List<ServiceCenterServiceOffer>> groupedServices = {};

    for (var service in availableServices) {
      final categoryName = _getCategoryName(service.serviceName ?? '');
      if (!groupedServices.containsKey(categoryName)) {
        groupedServices[categoryName] = [];
      }
      groupedServices[categoryName]!.add(service);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Services',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Available services for your ${selectedVehicle?['brand'] ?? 'vehicle'} ${selectedVehicle?['make'] ?? ''}',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          if (servicesLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: AppColors.primaryColor),
              ),
            )
          else
            if (availableServices.isEmpty)
              _buildEmptyServicesState()
            else
              ...groupedServices.entries.map((entry) =>
                  _buildServiceCategory(entry.key, entry.value)
              ).toList(),

          if (selectedServices.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildPriceSummary(),
          ],

          if (selectedServices.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildPrioritySelection(),
          ],

          if (selectedServices.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildNotesSection(),
          ],
        ],
      ),
    );
  }

  String _getCategoryName(String serviceName) {
    /// only for testing purpose
    final categoryMap = {
      'brake': 'Brake System',
      'engine': 'Engine Service',
      'oil': 'Oil Change',
      'tire': 'Tire Service',
      'transmission': 'Transmission',
      'air conditioning': 'Air Conditioning',
      'battery': 'Battery Service',
      'electrical': 'Electrical System',
      'suspension': 'Suspension',
      'exhaust': 'Exhaust System',
      'maintenance': 'Maintenance',
      'repair': 'General Repair',
      'diagnostic': 'Diagnostics',
      'body': 'Body Work',
    };

    for (var key in categoryMap.keys) {
      if (serviceName.toLowerCase().contains(key)) {
        return categoryMap[key]!;
      }
    }
    return 'Other Services';
  }

  Widget _buildServiceCategory(String categoryName,
      List<ServiceCenterServiceOffer> services) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              categoryName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...services.map((service) => _buildServiceCard(service)).toList(),
        ],
      ),
    );
  }

  Widget _buildServiceCard(ServiceCenterServiceOffer service) {
    final isSelected = selectedServices.contains(service);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        elevation: isSelected ? 4 : 1,
        shadowColor: isSelected
            ? AppColors.primaryColor.withOpacity(0.3)
            : Colors.black.withOpacity(0.1),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              if (isSelected) {
                selectedServices.remove(service);
              } else {
                selectedServices.add(service);
              }
              _calculateTotalPrice();
            });
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppColors.primaryColor
                    : AppColors.borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getServiceColor(service.serviceName ?? '')
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getServiceIcon(service.serviceName ?? ''),
                    color: _getServiceColor(service.serviceName ?? ''),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.serviceName ?? service.serviceDescription,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        service.serviceDescription,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildServicePriceChip(service),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Container(
                        margin: EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Est: ${service.duration}min',
                          style: TextStyle(
                            color: AppColors.accentColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryColor
                        : AppColors.surfaceColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected
                        ? Icons.check
                        : Icons.add,
                    color: isSelected
                        ? Colors.white
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServicePriceChip(ServiceCenterServiceOffer service) {
    bool hasFixedPartPrice = service.partPrice > 0;
    bool hasFixedLabourPrice = service.labourPrice > 0;

    if (hasFixedPartPrice && hasFixedLabourPrice) {
      double total = service.partPrice + service.labourPrice;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.successColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'RM${total.toStringAsFixed(2)}',
          style: TextStyle(
            color: AppColors.successColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else {
      double minTotal = service.partPriceMin + service.labourPriceMin;
      double maxTotal = service.partPriceMax + service.labourPriceMax;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.warningColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
          style: TextStyle(
            color: AppColors.warningColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  Widget _buildEmptyServicesState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.build_circle_outlined,
              size: 80,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 24),
            Text(
              'No Services Available',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This service center doesn\'t offer services for your vehicle model.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          if (totalFixedPrice > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Fixed Total',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    )),
                Text(
                  'RM${totalFixedPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.successColor,
                  ),
                ),
              ],
            ),

          if (totalRangePrice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Range',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    )),
                Text(
                  totalRangePrice,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warningColor,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 12),
          Text(
            'Total services selected: ${selectedServices.length}',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySelection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Urgency Level',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildUrgencyChip('normal', 'Normal', AppColors.successColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUrgencyChip('urgent', 'Urgent', AppColors.errorColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyChip(String value, String label, Color color) {
    final isSelected = urgencyLevel == value;
    return InkWell(
      onTap: () => setState(() => urgencyLevel = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : AppColors.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? color : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Additional Notes (Optional)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Any specific requests or issues to mention...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
              ),
              filled: true,
              fillColor: AppColors.cardColor,
            ),
            onChanged: (value) => additionalNotes = value,
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Date & Time',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your preferred date and time for the service',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          // Date Selection
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Date',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: AppColors.primaryColor),
                        const SizedBox(width: 12),
                        Text(
                          selectedDate != null
                              ? DateFormat('EEEE, MMM dd, yyyy').format(selectedDate!)
                              : 'Choose Date',
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedDate != null
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Time Selection
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Time',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (picked != null) {
                      setState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time, color: AppColors.primaryColor),
                        const SizedBox(width: 12),
                        Text(
                          selectedTime != null
                              ? selectedTime!.format(context)
                              : 'Choose Time',
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedTime != null
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Operating Hours Info
          if (widget.serviceCenter.operatingHours.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accentColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.accentColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Operating Hours',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...widget.serviceCenter.operatingHours.take(3).map((hours) {
                    final isClosed = hours['isClosed'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${hours['day']}: ${isClosed ? 'Closed' : '${hours['open']} - ${hours['close']}'}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Confirm Booking',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Review your booking details before confirming',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),

          // Service Center Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service Center',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.serviceCenter.images.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          widget.serviceCenter.images.first, // Already decrypted
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 60,
                              height: 60,
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
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('Service center image error: $error');
                            return Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.home_repair_service,
                                  color: AppColors.textMuted),
                            );
                          },
                        ),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.serviceCenter.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.serviceCenter.city,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Vehicle Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_car,
                        color: AppColors.primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${selectedVehicle?['brand'] ?? selectedVehicle?['make']} ${selectedVehicle?['model']}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${selectedVehicle?['year']} • ${selectedVehicle?['plate_number']}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Services Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected Services (${selectedServices.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                ...selectedServices.map((service) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getServiceIcon(service.serviceName ?? ''),
                        color: _getServiceColor(service.serviceName ?? ''),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          service.serviceName ?? service.serviceDescription,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${service.duration}min',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )).toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Schedule Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schedule',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.calendar_today, color: AppColors.accentColor),
                    const SizedBox(width: 12),
                    Text(
                      selectedDate != null
                          ? DateFormat('EEEE, MMM dd, yyyy').format(selectedDate!)
                          : 'Date not selected',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, color: AppColors.accentColor),
                    const SizedBox(width: 12),
                    Text(
                      selectedTime?.format(context) ?? 'Time not selected',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      urgencyLevel == 'urgent' ? Icons.priority_high : Icons.schedule,
                      color: urgencyLevel == 'urgent' ? AppColors.errorColor : AppColors.successColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Priority: ${urgencyLevel.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Price Summary
          if (selectedServices.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primaryColor.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Cost',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (totalFixedPrice > 0)
                    Text(
                      'Fixed: RM${totalFixedPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.successColor,
                      ),
                    ),
                  if (totalRangePrice.isNotEmpty)
                    Text(
                      'Estimated: $totalRangePrice',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warningColor,
                      ),
                    ),
                  if (totalFixedPrice == 0.0 && totalRangePrice.isEmpty)
                    Text(
                      'Price will be quoted upon inspection',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

          // Additional Notes
          if (additionalNotes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional Notes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    additionalNotes,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
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

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        border: Border(top: BorderSide(color: AppColors.borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: loading ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: BorderSide(color: AppColors.borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (currentStep > 0) const SizedBox(width: 16),
          Expanded(
            flex: currentStep == 0 ? 1 : 2,
            child: ElevatedButton(
              onPressed: loading || !_canProceed()
                  ? null
                  : (currentStep == 3 ? _confirmBooking : _nextStep),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: loading
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
                  : Text(
                currentStep == 3 ? 'Confirm Booking' : 'Continue',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// testing purpose
  Color _getServiceColor(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('brake')) return AppColors.errorColor;
    if (name.contains('engine')) return Colors.redAccent;
    if (name.contains('oil')) return Colors.orangeAccent;
    if (name.contains('tire') || name.contains('tyre')) return Colors.blueAccent;
    if (name.contains('battery')) return Colors.green;
    if (name.contains('air conditioning') || name.contains('ac')) return Colors.cyan;
    if (name.contains('transmission')) return Colors.purple;
    if (name.contains('suspension')) return Colors.indigo;
    return AppColors.accentColor;
  }

  /// testing purpose
  IconData _getServiceIcon(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('brake')) return Icons.disc_full;
    if (name.contains('engine')) return Icons.build_circle;
    if (name.contains('oil')) return Icons.local_gas_station;
    if (name.contains('tire') || name.contains('tyre')) return Icons.tire_repair;
    if (name.contains('battery')) return Icons.battery_charging_full;
    if (name.contains('air conditioning') || name.contains('ac')) return Icons.ac_unit;
    if (name.contains('transmission')) return Icons.settings;
    if (name.contains('suspension')) return Icons.drive_eta;
    if (name.contains('diagnostic')) return Icons.search;
    return Icons.build;
  }
}