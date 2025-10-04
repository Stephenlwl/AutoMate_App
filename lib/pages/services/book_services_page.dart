import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'package:automate_application/model/service_center_service_package_offer_model.dart';

class TimeRange {
  final TimeOfDay start;
  final TimeOfDay end;

  TimeRange(this.start, this.end);
}

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

  Map<String, Map<String, dynamic>> offerTiers = {};
  Map<String, Map<String, dynamic>> effectivePricing = {};

  // Add these two missing maps
  Map<String, int> packageDurations = {};
  Map<String, Map<String, double>> packagePricing = {};

  // Form data
  String? selectedVehicleId;
  Map<String, dynamic>? selectedVehicle;
  List<ServiceCenterServiceOffer> selectedServices = [];
  ServicePackage? selectedPackage;
  String selectionType = 'individual'; // 'individual' or 'package'
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  String urgencyLevel = 'normal';
  String additionalNotes = '';

  String _normalize(String s) => s.toLowerCase().trim();

  Map<String, List<ServiceCenterServiceOffer>> groupedServices = {};
  List<Map<String, dynamic>> userVehicles = [];
  List<ServiceCenterServiceOffer> availableServices = [];
  List<ServicePackage> availablePackages = [];
  List<Map<String, dynamic>> serviceCategories = [];
  List<TimeOfDay> availableTimeSlots = [];
  List<String> blockedDates = [];
  List<String> existingBookings = [];
  bool loading = false;
  bool servicesLoading = false;
  double totalFixedPrice = 0.0;
  String totalRangePrice = '';
  bool isServiceCenterOpen = false;
  int totalEstimatedDuration = 0; // in minutes

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadServiceCategories();
    _checkServiceCenterStatus();
    _loadSpecialClosures();
    if (selectedDate != null) {
      _generateTimeSlotsForDate(selectedDate!);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        final vehicles = List<Map<String, dynamic>>.from(
          data['vehicles'] ?? [],
        );

        final approvedVehicles =
            vehicles.where((v) => (v['status'] ?? '') == 'approved').toList();

        setState(() {
          userVehicles = approvedVehicles;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadServiceCategories() async {
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('services_categories')
              .where('active', isEqualTo: true)
              .where('status', isEqualTo: 'approved')
              .get();

      setState(() {
        serviceCategories =
            query.docs
                .map(
                  (doc) => {
                    'id': doc.id,
                    'name': doc['name'] ?? '',
                    'description': doc['description'] ?? '',
                  },
                )
                .toList();
      });
    } catch (e) {
      debugPrint('Error loading service categories: $e');
    }
  }

  Future<void> _loadSpecialClosures() async {
    try {
      List<String> blocked = [];

      if (widget.serviceCenter.specialClosures != null) {
        for (var closure in widget.serviceCenter.specialClosures!) {
          if (closure['date'] != null) {
            blocked.add(closure['date'] as String);
          }
        }
      }

      setState(() {
        blockedDates = blocked;
      });
    } catch (e) {
      debugPrint('Error loading special closures: $e');
    }
  }

  bool _isDateClosed(DateTime date) {
    if (date == null) return false;

    String dateStr = DateFormat('yyyy-MM-dd').format(date);
    if (blockedDates.contains(dateStr)) {
      return true;
    }

    final dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    final dayName = dayNames[date.weekday - 1];

    final dayHours = widget.serviceCenter.operatingHours.firstWhere(
          (hours) => hours['day'] == dayName,
      orElse: () => {},
    );

    return dayHours.isEmpty || dayHours['isClosed'] == true;
  }

  void _checkServiceCenterStatus() {
    final now = DateTime.now();
    final dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    final currentDay = dayNames[now.weekday - 1];

    final todayHours = widget.serviceCenter.operatingHours.firstWhere(
      (hours) => hours['day'] == currentDay,
      orElse: () => {},
    );

    if (todayHours.isNotEmpty) {
      final isClosed = todayHours['isClosed'] == true;
      if (!isClosed) {
        final openTime = _parseTimeString(todayHours['open'] ?? '09:00');
        final closeTime = _parseTimeString(todayHours['close'] ?? '18:00');
        final currentTime = TimeOfDay.now();

        setState(() {
          isServiceCenterOpen = _isTimeInRange(
            currentTime,
            openTime,
            closeTime,
          );
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

  String _formatDuration(int minutes) {
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

  Future<Map<String, int>> _getServiceCenterHours() async {
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final selectedDayName = dayNames[selectedDate!.weekday - 1];

    final dayHours = widget.serviceCenter.operatingHours.firstWhere(
      (hours) => hours['day'] == selectedDayName,
      orElse: () => {},
    );

    if (dayHours.isEmpty || dayHours['isClosed'] == true) {
      return {'openHour': 9, 'closeHour': 18}; // Default hours
    }

    final openTime = _parseTimeString(dayHours['open'] ?? '09:00');
    final closeTime = _parseTimeString(dayHours['close'] ?? '18:00');

    return {'openHour': openTime.hour, 'closeHour': closeTime.hour};
  }

  Future<List<TimeRange>> _getServiceCenterOccupiedSlots(DateTime date) async {
    List<TimeRange> occupiedSlots = [];

    try {
      final query =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
              .where('scheduledDate', isEqualTo: Timestamp.fromDate(date))
              .where('status', whereIn: ['pending', 'confirmed', 'assigned', 'in_progress', 'ready_to_collect'])
              .get();

      for (var doc in query.docs) {
        final data = doc.data();
        final timeStr = data['scheduledTime'] as String?;
        final duration = data['estimatedDuration'] as int? ?? 60;

        if (timeStr != null) {
          final timeParts = timeStr.split(':');
          final startHour = int.parse(timeParts[0]);
          final startMinute = int.parse(timeParts[1]);

          final startTime = TimeOfDay(hour: startHour, minute: startMinute);
          final endMinutes = startHour * 60 + startMinute + duration;
          final endTime = TimeOfDay(
            hour: endMinutes ~/ 60,
            minute: endMinutes % 60,
          );

          occupiedSlots.add(TimeRange(startTime, endTime));
        }
      }
    } catch (e) {
      debugPrint('Error loading occupied slots: $e');
    }

    return occupiedSlots;
  }

  bool _isMultiDayService(DateTime? date) {
    if (date == null) return false;

    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayName = dayNames[date.weekday - 1];

    final dayHours = widget.serviceCenter.operatingHours.firstWhere(
      (hours) => hours['day'] == dayName,
      orElse: () => {},
    );

    if (dayHours.isEmpty || dayHours['isClosed'] == true) {
      return false;
    }

    final openTime = _parseTimeString(dayHours['open'] ?? '09:00');
    final closeTime = _parseTimeString(dayHours['close'] ?? '18:00');

    final dailyOperatingMinutes =
        (closeTime.hour * 60 + closeTime.minute) -
        (openTime.hour * 60 + openTime.minute);

    return totalEstimatedDuration > dailyOperatingMinutes;
  }

  Future<void> _generateTimeSlotsForDate(DateTime date) async {
    setState(() {
      availableTimeSlots.clear();
      loading = true;
    });

    try {
      List<TimeOfDay> slots = [];

      if (_isMultiDayService(date)) {
        // For multi-day services, we need to check consecutive days
        slots = await _findMultiDayTimeSlots(date);
      } else {
        // For single day services, use the original logic
        slots = await _findSingleDayTimeSlots(date);
      }

      setState(() {
        availableTimeSlots = slots;
        loading = false;
      });
    } catch (e) {
      setState(() {
        availableTimeSlots = [];
        loading = false;
      });
      debugPrint('Error generating time slots: $e');
    }
  }

  int _getDailyOperatingMinutes(DateTime date) {
    final dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dayName = dayNames[date.weekday - 1];

    final dayHours = widget.serviceCenter.operatingHours.firstWhere(
      (hours) => hours['day'] == dayName,
      orElse: () => {},
    );

    if (dayHours.isEmpty || dayHours['isClosed'] == true) {
      return 0;
    }

    final openTime = _parseTimeString(dayHours['open'] ?? '09:00');
    final closeTime = _parseTimeString(dayHours['close'] ?? '18:00');

    return (closeTime.hour * 60 + closeTime.minute) -
        (openTime.hour * 60 + openTime.minute);
  }

  Future<List<TimeOfDay>> _findMultiDayTimeSlots(DateTime startDate) async {
    List<TimeOfDay> availableSlots = [];

    // Calculate how many days we need based on actual operating hours
    int totalDaysNeeded = 1;
    int remainingDuration = totalEstimatedDuration;

    for (
      int dayOffset = 0;
      dayOffset < 60 && remainingDuration > 0;
      dayOffset++
    ) {
      DateTime currentDate = startDate.add(Duration(days: dayOffset));
      int dailyMinutes = _getDailyOperatingMinutes(currentDate);

      if (dailyMinutes > 0) {
        remainingDuration -= dailyMinutes;
        if (remainingDuration > 0) {
          totalDaysNeeded++;
        }
      }
    }

    // Check if we have enough consecutive available days
    for (int dayOffset = 0; dayOffset < totalDaysNeeded; dayOffset++) {
      DateTime currentDate = startDate.add(Duration(days: dayOffset));
      if (_isDateClosed(currentDate)) {
        return []; // Not enough consecutive available days
      }
    }

    // Get service center hours for the start date
    final serviceCenterHours = await _getServiceCenterHours();
    final startDateOccupiedSlots = await _getServiceCenterOccupiedSlots(
      startDate,
    );

    // Generate possible start times
    for (
      int hour = serviceCenterHours['openHour']!;
      hour <= serviceCenterHours['closeHour']! - 1;
      hour++
    ) {
      for (int minute = 0; minute < 60; minute += 60) {
        final startTime = TimeOfDay(hour: hour, minute: minute);

        // Check if this start time works for the multi-day service
        bool isSlotAvailable = await _isMultiDaySlotAvailable(
          startDate,
          startTime,
          totalDaysNeeded,
        );

        if (isSlotAvailable) {
          availableSlots.add(startTime);

          // Limit the number of slots to avoid too many options
          if (availableSlots.length >= 15) break;
        }
      }
      if (availableSlots.length >= 15) break;
    }

    return availableSlots;
  }

  Future<int> _calculateDaysNeeded(DateTime startDate) async {
    int totalDaysNeeded = 1;
    int remainingDuration = totalEstimatedDuration;

    for (
      int dayOffset = 0;
      dayOffset < 60 && remainingDuration > 0;
      dayOffset++
    ) {
      DateTime currentDate = startDate.add(Duration(days: dayOffset));
      int dailyMinutes = _getDailyOperatingMinutes(currentDate);

      if (dailyMinutes > 0) {
        remainingDuration -= dailyMinutes;
        if (remainingDuration > 0) {
          totalDaysNeeded++;
        }
      }
    }

    return totalDaysNeeded;
  }

  Future<bool> _isMultiDaySlotAvailable(
    DateTime startDate,
    TimeOfDay startTime,
    int daysNeeded,
  ) async {
    int remainingDuration = totalEstimatedDuration;
    DateTime currentDate = startDate;
    TimeOfDay currentStartTime = startTime;

    for (int day = 0; day < daysNeeded && remainingDuration > 0; day++) {
      final DateTime checkDate = startDate.add(Duration(days: day));

      // Get service center hours for this day
      final dayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final dayName = dayNames[checkDate.weekday - 1];
      final dayHours = widget.serviceCenter.operatingHours.firstWhere(
        (hours) => hours['day'] == dayName,
        orElse: () => {},
      );

      if (dayHours.isEmpty || dayHours['isClosed'] == true) {
        return false;
      }

      final openTime = _parseTimeString(dayHours['open'] ?? '09:00');
      final closeTime = _parseTimeString(dayHours['close'] ?? '18:00');

      // Calculate available time for this day
      final int dayStartMinutes =
          (day == 0)
              ? currentStartTime.hour * 60 + currentStartTime.minute
              : openTime.hour * 60 + openTime.minute;

      final int dayEndMinutes = closeTime.hour * 60 + closeTime.minute;
      final int availableMinutesToday = dayEndMinutes - dayStartMinutes;

      // Check for conflicts with occupied slots
      final dayOccupiedSlots = await _getServiceCenterOccupiedSlots(checkDate);
      for (final occupied in dayOccupiedSlots) {
        final occupiedStart = occupied.start.hour * 60 + occupied.start.minute;
        final occupiedEnd = occupied.end.hour * 60 + occupied.end.minute;

        // Check if our service time conflicts with occupied slot
        if (dayStartMinutes < occupiedEnd &&
            (dayStartMinutes +
                    remainingDuration.clamp(0, availableMinutesToday)) >
                occupiedStart) {
          return false;
        }
      }

      // Deduct the time we can use today from remaining duration
      final int timeUsedToday = remainingDuration.clamp(
        0,
        availableMinutesToday,
      );
      remainingDuration -= timeUsedToday;
    }

    return remainingDuration <= 0;
  }

  Future<List<TimeOfDay>> _findSingleDayTimeSlots(DateTime date) async {
    List<TimeOfDay> slots = [];

    if (_isDateClosed(date)) {
      return slots;
    }

    final serviceCenterHours = await _getServiceCenterHours();
    final occupiedSlots = await _getServiceCenterOccupiedSlots(date);

    for (
      int hour = serviceCenterHours['openHour']!;
      hour <= serviceCenterHours['closeHour']! - 1;
      hour++
    ) {
      for (int minute = 0; minute < 60; minute += 60) {
        final startTime = TimeOfDay(hour: hour, minute: minute);
        final startMinutes = hour * 60 + minute;
        final endMinutes = startMinutes + totalEstimatedDuration;
        final closeMinutes = serviceCenterHours['closeHour']! * 60;

        // Check if slot fits within operating hours
        if (endMinutes <= closeMinutes) {
          // Check for conflicts with occupied slots
          bool hasConflict = false;
          for (final occupied in occupiedSlots) {
            final occupiedStart =
                occupied.start.hour * 60 + occupied.start.minute;
            final occupiedEnd = occupied.end.hour * 60 + occupied.end.minute;

            if (startMinutes < occupiedEnd && endMinutes > occupiedStart) {
              hasConflict = true;
              break;
            }
          }

          if (!hasConflict) {
            // Check if it's today and time hasn't passed
            if (date.day == DateTime.now().day &&
                date.month == DateTime.now().month &&
                date.year == DateTime.now().year) {
              TimeOfDay now = TimeOfDay.now();
              int nowMinutes = now.hour * 60 + now.minute;
              if (startMinutes > nowMinutes) {
                slots.add(startTime);
              }
            } else {
              slots.add(startTime);
            }
          }
        }
      }
    }

    return slots;
  }

  String _getCategoryNameSync(ServiceCenterServiceOffer service) {
    // Try to get from cached category names first
    if (_categoryNameCache.containsKey(service.categoryId)) {
      return _categoryNameCache[service.categoryId]!;
    }

    return 'Other Services';
  }

  // Add this map to cache category names (add this as a class variable)
  Map<String, String> _categoryNameCache = {};

  // Method to preload all category names for better performance
  Future<void> _preloadCategoryNames() async {
    try {
      final categoriesQuery =
          await FirebaseFirestore.instance
              .collection('services_categories')
              .where('active', isEqualTo: true)
              .where('status', isEqualTo: 'approved')
              .get();

      for (var categoryDoc in categoriesQuery.docs) {
        final categoryData = categoryDoc.data();
        final categoryName = categoryData['name'] ?? 'Unknown Category';
        _categoryNameCache[categoryDoc.id] = categoryName;
      }

      debugPrint('Preloaded ${_categoryNameCache.length} category names');
    } catch (e) {
      debugPrint('Error preloading category names: $e');
    }
  }

  Future<void> _loadServicesForVehicle() async {
    if (selectedVehicle == null) return;

    setState(() {
      servicesLoading = true;
      availableServices.clear();
      availablePackages.clear();
      offerTiers.clear();
      effectivePricing.clear();
      groupedServices.clear();
    });

    try {
      // Extract vehicle details
      final vehicleMake = _normalize(
        selectedVehicle!['make']?.toString() ?? '',
      );
      final vehicleModel = _normalize(
        selectedVehicle!['model']?.toString() ?? '',
      );
      final vehicleYear = selectedVehicle!['year']?.toString() ?? '';
      final vehicleFuelType = _normalize(
        selectedVehicle!['fuelType']?.toString() ?? '',
      );

      String vehicleDisplacement = '';
      final displacementData = selectedVehicle!['displacement'];
      if (displacementData != null) {
        String displacementStr = displacementData.toString();
        if (displacementStr.startsWith('[') && displacementStr.endsWith(']')) {
          String innerContent = displacementStr.substring(
            1,
            displacementStr.length - 1,
          );
          List<String> values =
              innerContent.split(',').map((e) => e.trim()).toList();
          if (values.isNotEmpty && values.first.isNotEmpty) {
            vehicleDisplacement = values.first;
          }
        } else if (displacementData is List && displacementData.isNotEmpty) {
          vehicleDisplacement = displacementData.first.toString();
        } else if (displacementStr.isNotEmpty) {
          vehicleDisplacement = displacementStr;
        }
      }

      final vehicleSizeClass = _normalize(
        selectedVehicle!['sizeClass']?.toString() ?? '',
      );

      // Load service offers
      final offersQuery =
          await FirebaseFirestore.instance
              .collection('service_center_services_offer')
              .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
              .where('active', isEqualTo: true)
              .get();

      // Load tiers
      final tiersQuery =
          await FirebaseFirestore.instance
              .collection('service_center_service_tiers')
              .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
              .get();

      Map<String, Map<String, dynamic>> tiersMap = {};
      for (var tierDoc in tiersQuery.docs) {
        tiersMap[tierDoc.id] = tierDoc.data();
      }

      List<ServiceCenterServiceOffer> individualServices = [];
      Set<String> packageIds = {};
      List<ServiceCenterServiceOffer> compatiblePackageOffers = [];

      for (var offerDoc in offersQuery.docs) {
        final offerData = offerDoc.data();
        final offer = ServiceCenterServiceOffer.fromFirestore(
          offerDoc.id,
          offerData,
        );

        bool isCompatible = false;
        Map<String, dynamic>? effectiveTier;

        // Check compatibility with tiers or direct offer
        if (offer.tierId != null && tiersMap.containsKey(offer.tierId)) {
          final tierData = tiersMap[offer.tierId!]!;
          effectiveTier = tierData;

          isCompatible = _checkVehicleCompatibilityWithTier(
            tierData,
            vehicleMake,
            vehicleModel,
            vehicleYear,
            vehicleFuelType,
            vehicleDisplacement,
            vehicleSizeClass,
          );

          if (isCompatible) {
            offerTiers[offer.id] = tierData;
            Map<String, dynamic> pricing = {};
            pricing['price'] = tierData['price'] ?? offer.partPrice;
            pricing['priceMin'] = tierData['priceMin'] ?? offer.partPriceMin;
            pricing['priceMax'] = tierData['priceMax'] ?? offer.partPriceMax;
            pricing['labourPrice'] =
                tierData['labourPrice'] ?? offer.labourPrice;
            pricing['labourPriceMin'] =
                tierData['labourPriceMin'] ?? offer.labourPriceMin;
            pricing['labourPriceMax'] =
                tierData['labourPriceMax'] ?? offer.labourPriceMax;
            pricing['duration'] = tierData['duration'] ?? offer.duration;
            effectivePricing[offer.id] = pricing;
          }
        } else {
          isCompatible = _checkVehicleCompatibilityWithOffer(
            offer,
            vehicleMake,
            vehicleModel,
            vehicleYear,
            vehicleFuelType,
            vehicleDisplacement,
            vehicleSizeClass,
          );
        }

        if (isCompatible) {
          await _loadServiceName(offer);

          // Check if this offer is part of a package or individual service
          if (offer.servicePackageId != null &&
              offer.servicePackageId!.isNotEmpty) {
            packageIds.add(offer.servicePackageId!);
            compatiblePackageOffers.add(offer);
          } else if (offer.serviceId!.isNotEmpty) {
            individualServices.add(offer);
          }
        }
      }

      await _groupServicesByCategory(individualServices);

      List<ServicePackage> compatiblePackages = [];
      if (packageIds.isNotEmpty) {
        for (String packageId in packageIds) {
          try {
            final packageDoc =
                await FirebaseFirestore.instance
                    .collection('service_packages')
                    .doc(packageId)
                    .get();

            if (packageDoc.exists) {
              final packageData = packageDoc.data()!;
              if (packageData['active'] == true &&
                  packageData['serviceCenterId'] == widget.serviceCenter.id) {
                // Verify package compatibility
                bool packageCompatible =
                    _checkPackageCompatibilityByCompatibleOffers(
                      packageId,
                      compatiblePackageOffers,
                    );

                if (packageCompatible) {
                  final package = ServicePackage.fromFirestore(
                    packageDoc.id,
                    packageData,
                  );
                  compatiblePackages.add(package);

                  // Calculate package pricing and duration
                  await _calculatePackageDetails(package);
                }
              }
            }
          } catch (e) {
            debugPrint('Error loading package $packageId: $e');
          }
        }
      }

      setState(() {
        availableServices = individualServices;
        availablePackages = compatiblePackages;
        servicesLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading services for vehicle: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        servicesLoading = false;
      });
    }
  }

  Future<void> _calculatePackageDetails(ServicePackage package) async {
    try {
      final pricing = await _calculatePackagePricing(package);
      int duration = pricing['duration'] ?? package.estimatedDuration;

      packageDurations[package.id] = duration;
      packagePricing[package.id] = {
        'fixedPrice':
            (pricing['totalPartPrice'] as double) +
            (pricing['totalLabourPrice'] as double),
        'minPrice':
            (pricing['minPartPrice'] as double) +
            (pricing['minLabourPrice'] as double),
        'maxPrice':
            (pricing['maxPartPrice'] as double) +
            (pricing['maxLabourPrice'] as double),
        'partPrice': pricing['totalPartPrice'] as double,
        'labourPrice': pricing['totalLabourPrice'] as double,
        'partPriceMin': pricing['minPartPrice'] as double,
        'partPriceMax': pricing['maxPartPrice'] as double,
        'labourPriceMin': pricing['minLabourPrice'] as double,
        'labourPriceMax': pricing['maxLabourPrice'] as double,
      };
    } catch (e) {
      debugPrint('Error calculating package details for ${package.id}: $e');
    }
  }

  Future<Map<String, dynamic>> _calculatePackagePricing(
    ServicePackage package,
  ) async {
    double totalPartPrice = 0.0;
    double totalLabourPrice = 0.0;
    double totalPartPriceMin = 0.0;
    double totalPartPriceMax = 0.0;
    double totalLabourPriceMin = 0.0;
    double totalLabourPriceMax = 0.0;
    int totalDuration = 0;
    int validOffers = 0;

    try {
      // Get active service offers for this package
      final packageOffersQuery =
          await FirebaseFirestore.instance
              .collection('service_center_services_offer')
              .where('servicePackageId', isEqualTo: package.id)
              .where('active', isEqualTo: true)
              .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
              .get();

      Set<String> requiredTierIds = {};
      for (var offerDoc in packageOffersQuery.docs) {
        final offerData = offerDoc.data();
        final tierIdValue = offerData['tierId'];
        if (tierIdValue != null && tierIdValue.toString().isNotEmpty) {
          requiredTierIds.add(tierIdValue.toString());
        }
      }

      // Load tier data
      Map<String, Map<String, dynamic>> tiersMap = {};
      if (requiredTierIds.isNotEmpty) {
        for (String tierId in requiredTierIds) {
          try {
            final tierDoc =
                await FirebaseFirestore.instance
                    .collection('service_center_service_tiers')
                    .doc(tierId)
                    .get();

            if (tierDoc.exists) {
              tiersMap[tierId] = tierDoc.data() as Map<String, dynamic>;
            }
          } catch (e) {
            debugPrint('Error loading tier $tierId: $e');
          }
        }
      }

      // Vehicle details for compatibility check
      String vehicleMake = _normalize(
        selectedVehicle!['make']?.toString() ?? '',
      );
      String vehicleModel = _normalize(
        selectedVehicle!['model']?.toString() ?? '',
      );
      String vehicleYear = selectedVehicle!['year']?.toString() ?? '';
      String vehicleFuelType = _normalize(
        selectedVehicle!['fuelType']?.toString() ?? '',
      );
      String vehicleDisplacement = _extractDisplacement(
        selectedVehicle!['displacement'],
      );
      String vehicleSizeClass = _normalize(
        selectedVehicle!['sizeClass']?.toString() ?? '',
      );

      for (var offerDoc in packageOffersQuery.docs) {
        final offerData = offerDoc.data();
        final isOfferActive = offerData['active'] == true;
        if (!isOfferActive) continue;

        final offer = ServiceCenterServiceOffer.fromFirestore(
          offerDoc.id,
          offerData,
        );

        bool isOfferCompatible = false;
        Map<String, dynamic>? effectivePricing;

        if (offer.tierId != null && tiersMap.containsKey(offer.tierId)) {
          final tierData = tiersMap[offer.tierId!]!;
          isOfferCompatible = _checkVehicleCompatibilityWithTier(
            tierData,
            vehicleMake,
            vehicleModel,
            vehicleYear,
            vehicleFuelType,
            vehicleDisplacement,
            vehicleSizeClass,
          );

          if (isOfferCompatible) {
            effectivePricing = {
              'price': tierData['price'] ?? offer.partPrice,
              'priceMin': tierData['priceMin'] ?? offer.partPriceMin,
              'priceMax': tierData['priceMax'] ?? offer.partPriceMax,
              'labourPrice': tierData['labourPrice'] ?? offer.labourPrice,
              'labourPriceMin':
                  tierData['labourPriceMin'] ?? offer.labourPriceMin,
              'labourPriceMax':
                  tierData['labourPriceMax'] ?? offer.labourPriceMax,
              'duration': tierData['duration'] ?? offer.duration,
            };
          }
        } else {
          isOfferCompatible = _checkVehicleCompatibilityWithOffer(
            offer,
            vehicleMake,
            vehicleModel,
            vehicleYear,
            vehicleFuelType,
            vehicleDisplacement,
            vehicleSizeClass,
          );
        }

        if (isOfferCompatible) {
          double partPrice = effectivePricing?['price'] ?? offer.partPrice;
          double labourPrice =
              effectivePricing?['labourPrice'] ?? offer.labourPrice;
          double partPriceMin =
              effectivePricing?['priceMin'] ?? offer.partPriceMin;
          double partPriceMax =
              effectivePricing?['priceMax'] ?? offer.partPriceMax;
          double labourPriceMin =
              effectivePricing?['labourPriceMin'] ?? offer.labourPriceMin;
          double labourPriceMax =
              effectivePricing?['labourPriceMax'] ?? offer.labourPriceMax;
          int duration = effectivePricing?['duration'] ?? offer.duration;

          validOffers++;

          totalPartPrice += partPrice;
          totalLabourPrice += labourPrice;
          totalPartPriceMin += partPriceMin;
          totalPartPriceMax += partPriceMax;
          totalLabourPriceMin += labourPriceMin;
          totalLabourPriceMax += labourPriceMax;
          totalDuration += duration;
        }
      }

      if (validOffers == 0) {
        totalDuration = package.estimatedDuration;
      }

      return {
        'totalPartPrice': totalPartPrice,
        'totalLabourPrice': totalLabourPrice,
        'minPartPrice': totalPartPriceMin,
        'maxPartPrice': totalPartPriceMax,
        'minLabourPrice': totalLabourPriceMin,
        'maxLabourPrice': totalLabourPriceMax,
        'duration': totalDuration,
        'validOffers': validOffers,
      };
    } catch (e) {
      debugPrint('Error calculating package pricing for ${package.name}: $e');
      return {
        'totalPartPrice': 0.0,
        'totalLabourPrice': 0.0,
        'minPartPrice': 0.0,
        'maxPartPrice': 0.0,
        'minLabourPrice': 0.0,
        'maxLabourPrice': 0.0,
        'duration': package.estimatedDuration,
        'validOffers': 0,
      };
    }
  }

  String _extractDisplacement(dynamic displacementData) {
    if (displacementData == null) return '';
    String displacementStr = displacementData.toString();
    if (displacementStr.startsWith('[') && displacementStr.endsWith(']')) {
      String innerContent = displacementStr.substring(
        1,
        displacementStr.length - 1,
      );
      List<String> values =
          innerContent.split(',').map((e) => e.trim()).toList();
      if (values.isNotEmpty && values.first.isNotEmpty) {
        return values.first;
      }
    } else if (displacementData is List && displacementData.isNotEmpty) {
      return displacementData.first.toString();
    }
    return displacementStr;
  }

  bool _checkPackageCompatibilityByCompatibleOffers(
    String packageId,
    List<ServiceCenterServiceOffer> compatiblePackageOffers,
  ) {
    try {
      int compatibleOffersCount = 0;
      for (var offer in compatiblePackageOffers) {
        if (offer.servicePackageId == packageId) {
          compatibleOffersCount++;
        }
      }
      return compatibleOffersCount > 0;
    } catch (e) {
      debugPrint('Error checking package compatibility for $packageId: $e');
      return false;
    }
  }

  bool _checkVehicleCompatibilityWithTier(
    Map<String, dynamic> tierData,
    String vehicleMake,
    String vehicleModel,
    String vehicleYear,
    String vehicleFuelType,
    String vehicleDisplacement,
    String vehicleSizeClass,
  ) {
    try {
      // Check make compatibility
      final tierMakes = List<String>.from(tierData['makes'] ?? []);
      bool makeMatch =
          tierMakes.isEmpty ||
          tierMakes.any((make) => _normalize(make) == vehicleMake);
      if (!makeMatch) return false;

      // Check model compatibility
      final tierModels = Map<String, dynamic>.from(tierData['models'] ?? {});
      List<String> compatibleModels = [];
      for (var entry in tierModels.entries) {
        if (_normalize(entry.key) == vehicleMake) {
          compatibleModels = List<String>.from(entry.value ?? []);
          break;
        }
      }
      bool modelMatch =
          compatibleModels.isEmpty ||
          compatibleModels.any((model) => _normalize(model) == vehicleModel);
      if (!modelMatch) return false;

      // Check year compatibility
      final tierYears = Map<String, dynamic>.from(tierData['years'] ?? {});
      List<String> compatibleYears = [];
      for (var entry in tierYears.entries) {
        if (_normalize(entry.key) == vehicleModel) {
          final yearList = entry.value as List<dynamic>? ?? [];
          compatibleYears = yearList.map((year) => year.toString()).toList();
          break;
        }
      }
      bool yearMatch =
          compatibleYears.isEmpty || compatibleYears.contains(vehicleYear);
      if (!yearMatch) return false;

      return true;
    } catch (e) {
      debugPrint('Error in tier compatibility check: $e');
      return false;
    }
  }

  bool _checkVehicleCompatibilityWithOffer(
    ServiceCenterServiceOffer offer,
    String vehicleMake,
    String vehicleModel,
    String vehicleYear,
    String vehicleFuelType,
    String vehicleDisplacement,
    String vehicleSizeClass,
  ) {
    try {
      // Check make compatibility
      bool makeMatch =
          offer.makes.isEmpty ||
          offer.makes.any((make) => _normalize(make) == vehicleMake);
      if (!makeMatch) return false;

      // Check model compatibility
      List<String> compatibleModels = [];
      for (var entry in offer.models.entries) {
        if (_normalize(entry.key) == vehicleMake) {
          compatibleModels = entry.value;
          break;
        }
      }
      bool modelMatch =
          compatibleModels.isEmpty ||
          compatibleModels.any((model) => _normalize(model) == vehicleModel);
      if (!modelMatch) return false;

      // Check year compatibility
      List<String> compatibleYears = [];
      for (var entry in offer.years.entries) {
        if (_normalize(entry.key) == vehicleModel) {
          compatibleYears = entry.value;
          break;
        }
      }
      bool yearMatch =
          compatibleYears.isEmpty || compatibleYears.contains(vehicleYear);
      if (!yearMatch) return false;

      return true;
    } catch (e) {
      debugPrint('Error in offer compatibility check: $e');
      return false;
    }
  }

  Future<void> _loadServiceName(ServiceCenterServiceOffer offer) async {
    try {
      if (offer.serviceId!.isNotEmpty) {
        final serviceDoc =
            await FirebaseFirestore.instance
                .collection('services')
                .doc(offer.serviceId)
                .get();

        if (serviceDoc.exists) {
          final serviceData = serviceDoc.data()!;
          offer.serviceName = serviceData['name'] ?? offer.serviceDescription;
        }
      }
    } catch (e) {
      debugPrint('Error loading service name for ${offer.id}: $e');
      // Keep the existing serviceName or serviceDescription
    }
  }

  Future<void> _loadServicePackages() async {
    try {
      final packagesQuery =
          await FirebaseFirestore.instance
              .collection('service_packages')
              .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
              .where('active', isEqualTo: true)
              .get();

      List<ServicePackage> packages = [];

      for (var packageDoc in packagesQuery.docs) {
        final packageData = packageDoc.data();

        // Check if package services are compatible with vehicle
        bool packageCompatible = await _checkPackageCompatibility(packageData);

        if (packageCompatible) {
          final package = ServicePackage.fromFirestore(
            packageDoc.id,
            packageData,
          );
          packages.add(package);
        }
      }

      setState(() {
        availablePackages = packages;
      });
    } catch (e) {
      debugPrint('Error loading service packages: $e');
    }
  }

  Future<bool> _checkPackageCompatibility(
    Map<String, dynamic> packageData,
  ) async {
    try {
      final services = List<dynamic>.from(packageData['services'] ?? []);

      // Check if at least some services in the package are compatible
      int compatibleServicesCount = 0;

      for (var serviceData in services) {
        final serviceId = serviceData['serviceId'] as String?;
        if (serviceId == null) continue;

        // Check if we have compatible offers for this service
        final hasCompatibleOffer = availableServices.any(
          (offer) => offer.serviceId == serviceId,
        );

        if (hasCompatibleOffer) {
          compatibleServicesCount++;
        }
      }

      // Package is compatible if at least 70% of its services are compatible
      double compatibilityRatio =
          services.isEmpty ? 0 : compatibleServicesCount / services.length;
      return compatibilityRatio >= 0.7;
    } catch (e) {
      debugPrint('Error checking package compatibility: $e');
      return false;
    }
  }

  void _calculateTotalPrice() {
    if (selectionType == 'package' && selectedPackage != null) {
      final pricing =
          packagePricing[selectedPackage!.id] ??
          {'fixedPrice': 0.0, 'minPrice': 0.0, 'maxPrice': 0.0};
      final duration =
          packageDurations[selectedPackage!.id] ??
          selectedPackage!.estimatedDuration;

      setState(() {
        totalEstimatedDuration = duration;
        totalFixedPrice = pricing['fixedPrice'] ?? 0.0;
        if (pricing['minPrice'] != null &&
            pricing['maxPrice'] != null &&
            pricing['minPrice']! > 0 &&
            pricing['maxPrice']! > 0) {
          totalRangePrice =
              'RM${pricing['minPrice']!.toStringAsFixed(2)} - RM${pricing['maxPrice']!.toStringAsFixed(2)}';
        } else {
          totalRangePrice = '';
        }
      });
    } else if (selectionType == 'individual' && selectedServices.isNotEmpty) {
      double totalFixed = 0.0;
      double totalMin = 0.0;
      double totalMax = 0.0;
      int duration = 0;

      for (var service in selectedServices) {
        final effectivePricing = this.effectivePricing[service.id];

        double partPrice = effectivePricing?['price'] ?? service.partPrice;
        double labourPrice =
            effectivePricing?['labourPrice'] ?? service.labourPrice;
        double partPriceMin =
            effectivePricing?['priceMin'] ?? service.partPriceMin;
        double partPriceMax =
            effectivePricing?['priceMax'] ?? service.partPriceMax;
        double labourPriceMin =
            effectivePricing?['labourPriceMin'] ?? service.labourPriceMin;
        double labourPriceMax =
            effectivePricing?['labourPriceMax'] ?? service.labourPriceMax;
        int serviceDuration = effectivePricing?['duration'] ?? service.duration;

        duration += serviceDuration;

        // Calculate service totals - FIXED: Combine fixed and range pricing properly
        double serviceFixed = partPrice + labourPrice;
        double serviceMin = partPriceMin + labourPriceMin;
        double serviceMax = partPriceMax + labourPriceMax;

        // Add to totals
        totalFixed += serviceFixed;
        totalMin += serviceMin;
        totalMax += serviceMax;
      }

      setState(() {
        totalEstimatedDuration = duration;

        // Determine what to display based on the pricing mix
        bool hasFixedComponents = totalFixed > 0;
        bool hasRangeComponents = totalMax > totalMin && totalMax > 0;

        if (hasFixedComponents && hasRangeComponents) {
          // Show both fixed and range: Fixed price + (Min range - Max range)
          totalFixedPrice = totalFixed;
          totalRangePrice =
              'RM${(totalFixed + totalMin).toStringAsFixed(2)} - RM${(totalFixed + totalMax).toStringAsFixed(2)}';
        } else if (hasFixedComponents && !hasRangeComponents) {
          // Only fixed pricing available
          totalFixedPrice = totalFixed;
          totalRangePrice = '';
        } else if (hasRangeComponents) {
          // Only range pricing available
          totalFixedPrice = 0.0;
          totalRangePrice =
              'RM${totalMin.toStringAsFixed(2)} - RM${totalMax.toStringAsFixed(2)}';
        } else {
          // No pricing information
          totalFixedPrice = 0.0;
          totalRangePrice = '';
        }
      });
    } else {
      setState(() {
        totalFixedPrice = 0.0;
        totalRangePrice = '';
        totalEstimatedDuration = 0;
      });
    }

    // Regenerate time slots when services/packages change
    if (selectedDate != null) {
      _generateTimeSlotsForDate(selectedDate!);
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
      case 0:
        return selectedVehicle != null;
      case 1:
        return (selectionType == 'individual' && selectedServices.isNotEmpty) ||
            (selectionType == 'package' && selectedPackage != null);
      case 2:
        return selectedDate != null && selectedTime != null;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _confirmBooking() async {
    if (!_canProceed()) return;

    setState(() => loading = true);

    try {
      // Determine selection type
      final hasPackages = selectedPackage != null;
      final hasServices = selectedServices.isNotEmpty;
      final selectionType =
          hasPackages && hasServices
              ? 'both'
              : hasPackages
              ? 'package'
              : 'individual';

      // Prepare booking data
      Map<String, dynamic> bookingData = {
        'userId': widget.userId,
        'serviceCenterId': widget.serviceCenter.id,
        'vehicleId': selectedVehicleId,
        'vehicle': selectedVehicle,
        'selectionType': selectionType,
        'scheduledDate': Timestamp.fromDate(selectedDate!),
        'scheduledTime':
            '${selectedTime!.hour}:${selectedTime!.minute.toString().padLeft(2, '0')}',
        'estimatedDuration': totalEstimatedDuration,
        'urgencyLevel': urgencyLevel,
        'additionalNotes': additionalNotes,
        'totalFixedPrice': totalFixedPrice,
        'totalRangePrice': totalRangePrice,
        'totalAmount': totalFixedPrice,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Store packages data
      if (hasPackages && selectedPackage != null) {
        final packageDuration =
            packageDurations[selectedPackage!.id] ??
            selectedPackage!.estimatedDuration;
        final pricing =
            packagePricing[selectedPackage!.id] ??
            {'fixedPrice': 0.0, 'minPrice': 0.0, 'maxPrice': 0.0};

        double fixedPrice = pricing['fixedPrice'] ?? 0.0;
        double minPrice = pricing['minPrice'] ?? 0.0;
        double maxPrice = pricing['maxPrice'] ?? 0.0;

        bookingData['packages'] = [
          {
            'packageId': selectedPackage!.id,
            'packageName': selectedPackage!.name,
            'description': selectedPackage!.description,
            'estimatedDuration': packageDuration,
            'fixedPrice': fixedPrice,
            'rangePrice':
                minPrice > 0 && maxPrice > 0
                    ? 'RM${minPrice.toStringAsFixed(2)} - RM${maxPrice.toStringAsFixed(2)}'
                    : '',
            'services':
                selectedPackage!.services.map((service) {
                  return {
                    'serviceId': service.serviceId,
                    'serviceName': service.serviceName,
                    'categoryId': service.categoryId,
                    'categoryName': service.categoryName,
                    'duration': service.duration,
                    'labourPrice': service.labourPrice,
                    'partPrice': service.partPrice,
                    'labourPriceMin': service.labourPriceMin,
                    'labourPriceMax': service.labourPriceMax,
                    'partPriceMin': service.partPriceMin,
                    'partPriceMax': service.partPriceMax,
                  };
                }).toList(),
          },
        ];
      }

      // Store individual services data
      if (hasServices) {
        bookingData['services'] =
            selectedServices.map((service) {
              final effectivePricing = this.effectivePricing[service.id];
              return {
                'serviceId': service.serviceId,
                'serviceName':
                    service.serviceName ?? service.serviceDescription,
                'offerId': service.id,
                'duration': effectivePricing?['duration'] ?? service.duration,
                'partPrice': effectivePricing?['price'] ?? service.partPrice,
                'labourPrice':
                    effectivePricing?['labourPrice'] ?? service.labourPrice,
                'partPriceMin':
                    effectivePricing?['priceMin'] ?? service.partPriceMin,
                'partPriceMax':
                    effectivePricing?['priceMax'] ?? service.partPriceMax,
                'labourPriceMin':
                    effectivePricing?['labourPriceMin'] ??
                    service.labourPriceMin,
                'labourPriceMax':
                    effectivePricing?['labourPriceMax'] ??
                    service.labourPriceMax,
              };
            }).toList();
      }

      await FirebaseFirestore.instance
          .collection('service_bookings')
          .add(bookingData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Service booking confirmed successfully! ($selectionType)',
            ),
            backgroundColor: AppColors.successColor,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
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
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isServiceCenterOpen
                            ? AppColors.successColor.withOpacity(0.2)
                            : AppColors.errorColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          isServiceCenterOpen
                              ? AppColors.successColor
                              : AppColors.errorColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isServiceCenterOpen
                            ? Icons.access_time
                            : Icons.schedule,
                        size: 16,
                        color:
                            isServiceCenterOpen
                                ? AppColors.successColor
                                : AppColors.errorColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isServiceCenterOpen ? 'Open Now' : 'Closed',
                        style: TextStyle(
                          color:
                              isServiceCenterOpen
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
                  children: List.generate(
                    4,
                    (index) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: index < 3 ? 8 : 0),
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              index <= currentStep
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
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
            ...userVehicles.asMap().entries.map((entry) {
              final index = entry.key;
              final vehicle = entry.value;

              // Try different possible field names for vehicle ID
              final vehicleId = vehicle['plateNumber'] ?? index.toString();

              final isSelected = selectedVehicleId == vehicleId;

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
                        selectedVehicleId = vehicleId;
                        selectedVehicle = vehicle;
                        selectedServices.clear();
                        selectedPackage = null;
                        _calculateTotalPrice();
                      });
                      _loadServicesForVehicle();

                      debugPrint('Selected vehicle ID: $vehicleId');
                      debugPrint('Selected vehicle: ${vehicle['make']} ${vehicle['model']}');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
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
                          // Vehicle image and details...
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.textMuted)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Image.network(
                              'https://cdn.imagin.studio/getImage?customer=demo&make=${vehicle['make']}&modelFamily=${vehicle['model']}&modelYear=${vehicle['year']}&angle=01',
                              height: 90,
                              width: 90,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    height: 70,
                                    width: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.directions_car,
                                      size: 30,
                                      color: Colors.white,
                                    ),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${vehicle['make'] ?? 'Unknown'} ${vehicle['model'] ?? ''}',
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
                                      vehicle['plateNumber'] ?? 'N/A',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Selection indicator...
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryColor
                                    : AppColors.borderColor,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              isSelected ? Icons.check : Icons.radio_button_unchecked,
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
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSelection() {
    if (selectedVehicle == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.errorColor,
              ),
              const SizedBox(height: 16),
              Text(
                'No Vehicle Selected',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please go back and select a vehicle first',
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
              'Services available for your ${selectedVehicle!['make']} ${selectedVehicle!['model']} at ${widget.serviceCenter.name}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 24),

          // Service type selection tabs
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selectionType = 'individual';
                        selectedPackage = null;
                        _calculateTotalPrice();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            selectionType == 'individual'
                                ? AppColors.primaryColor
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Individual Services',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              selectionType == 'individual'
                                  ? Colors.white
                                  : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selectionType = 'package';
                        selectedServices.clear();
                        _calculateTotalPrice();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            selectionType == 'package'
                                ? AppColors.primaryColor
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Service Packages',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              selectionType == 'package'
                                  ? Colors.white
                                  : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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
          else if (selectionType == 'individual')
            _buildIndividualServices()
          else
            _buildServicePackages(),

          if ((selectionType == 'individual' && selectedServices.isNotEmpty) ||
              (selectionType == 'package' && selectedPackage != null)) ...[
            const SizedBox(height: 24),
            _buildPriceSummary(),
          ],

          const SizedBox(height: 24),
          _buildPrioritySelection(),
          const SizedBox(height: 24),
          _buildNotesSection(),
        ],
      ),
    );
  }

  Widget _buildServiceCategory(
    String categoryName,
    List<ServiceCenterServiceOffer> services,
  ) {
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

  Widget _buildIndividualServices() {
    if (availableServices.isEmpty) {
      return _buildEmptyServicesState();
    }

    if (groupedServices.isEmpty) {
      // Create a temporary grouping for display
      Map<String, List<ServiceCenterServiceOffer>> tempGroupedServices = {};

      for (var service in availableServices) {
        String categoryName = 'Other Services';

        // Try to get category name from cache or use fallback
        if (service.categoryId.isNotEmpty &&
            _categoryNameCache.containsKey(service.categoryId)) {
          categoryName = _categoryNameCache[service.categoryId]!;
        }
        if (!tempGroupedServices.containsKey(categoryName)) {
          tempGroupedServices[categoryName] = [];
        }
        tempGroupedServices[categoryName]!.add(service);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            tempGroupedServices.entries
                .map((entry) => _buildServiceCategory(entry.key, entry.value))
                .toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          groupedServices.entries
              .map((entry) => _buildServiceCategory(entry.key, entry.value))
              .toList(),
    );
  }

  Future<void> _groupServicesByCategory(
      List<ServiceCenterServiceOffer> services,
      ) async {
    try {
      Map<String, List<ServiceCenterServiceOffer>> categoryGroups = {};

      // Preload all category names for better performance
      await _preloadCategoryNames();

      for (var service in services) {
        String categoryName = 'Other Services';

        // First try to get category from service document
        if (service.serviceId.isNotEmpty) {
          try {
            final serviceDoc = await FirebaseFirestore.instance
                .collection('services')
                .doc(service.serviceId)
                .get();

            if (serviceDoc.exists) {
              final serviceData = serviceDoc.data()!;
              final categoryId = serviceData['categoryId'] as String?;

              if (categoryId != null && categoryId.isNotEmpty) {
                categoryName = _categoryNameCache[categoryId] ?? 'Other Services';
              }
            }
          } catch (e) {
            debugPrint('Error loading service category for ${service.serviceId}: $e');
          }
        }

        // If still no category found, try direct categoryId from offer
        if (categoryName == 'Other Services' && service.categoryId.isNotEmpty) {
          categoryName = _categoryNameCache[service.categoryId] ?? 'Other Services';
        }

        if (!categoryGroups.containsKey(categoryName)) {
          categoryGroups[categoryName] = [];
        }
        categoryGroups[categoryName]!.add(service);
      }

      setState(() {
        groupedServices = categoryGroups;
      });

      debugPrint(
        'Grouped services into ${categoryGroups.keys.length} categories: ${categoryGroups.keys.toList()}',
      );
    } catch (e) {
      debugPrint('Error grouping services by category: $e');
    }
  }

  // Future<void> _preloadCategoryNames() async {
  //   if (_categoryNameCache.isNotEmpty) return; // Already loaded
  //
  //   try {
  //     final categoriesQuery = await FirebaseFirestore.instance
  //         .collection('services_categories')
  //         .where('active', isEqualTo: true)
  //         .where('status', isEqualTo: 'approved')
  //         .get();
  //
  //     for (var categoryDoc in categoriesQuery.docs) {
  //       final categoryData = categoryDoc.data();
  //       final categoryName = categoryData['name']?.toString() ?? 'Unknown Category';
  //       _categoryNameCache[categoryDoc.id] = categoryName;
  //     }
  //
  //     debugPrint('Preloaded ${_categoryNameCache.length} category names');
  //   } catch (e) {
  //     debugPrint('Error preloading category names: $e');
  //   }
  // }
  //
  Widget _buildServicePackages() {
    if (availablePackages.isEmpty) {
      return _buildEmptyPackagesState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Packages (${availablePackages.length})',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...availablePackages
            .map((package) => _buildPackageCard(package))
            .toList(),
      ],
    );
  }

  Widget _buildServiceCard(ServiceCenterServiceOffer service) {
    final isSelected = selectedServices.contains(service);
    final effectivePricing = this.effectivePricing[service.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        elevation: isSelected ? 4 : 1,
        shadowColor:
            isSelected
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isSelected ? AppColors.primaryColor : AppColors.borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getServiceColor(
                      service.serviceName ?? '',
                    ).withOpacity(0.1),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildServicePriceChip(service, effectivePricing),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Est: ${effectivePricing?['duration'] ?? service.duration} minutes',
                              style: TextStyle(
                                color: AppColors.accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? AppColors.primaryColor
                            : AppColors.surfaceColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSelected ? Icons.check : Icons.add,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
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

  Widget _buildServicePriceChip(
    ServiceCenterServiceOffer service,
    Map<String, dynamic>? effectivePricing,
  ) {
    double partPrice = effectivePricing?['price'] ?? service.partPrice;
    double labourPrice =
        effectivePricing?['labourPrice'] ?? service.labourPrice;
    double partPriceMin = effectivePricing?['priceMin'] ?? service.partPriceMin;
    double partPriceMax = effectivePricing?['priceMax'] ?? service.partPriceMax;
    double labourPriceMin =
        effectivePricing?['labourPriceMin'] ?? service.labourPriceMin;
    double labourPriceMax =
        effectivePricing?['labourPriceMax'] ?? service.labourPriceMax;

    // Check pricing types (same logic as SearchServicesPage)
    bool hasAnyFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasAnyRangePricing =
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    // Calculate totals
    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getPricingBackgroundColor(
          hasAnyFixedPricing,
          hasAnyRangePricing,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getPricingBorderColor(hasAnyFixedPricing, hasAnyRangePricing),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main price display
          if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0)
            Text(
              'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.warningColor,
              ),
            )
          else if (hasAnyFixedPricing && !hasAnyRangePricing)
            Text(
              'RM${fixedTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.successColor,
              ),
            )
          else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0))
            Text(
              'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.warningColor,
              ),
            )
          else
            Text(
              'RM0.00',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted,
              ),
            ),

          const SizedBox(height: 4),

          // Detailed breakdown
          Text(
            _getDetailedPricingBreakdown(
              partPrice,
              labourPrice,
              partPriceMin,
              partPriceMax,
              labourPriceMin,
              labourPriceMax,
              hasAnyFixedPricing,
              hasAnyRangePricing,
            ),
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _getDetailedPricingBreakdown(
    double partPrice,
    double labourPrice,
    double partPriceMin,
    double partPriceMax,
    double labourPriceMin,
    double labourPriceMax,
    bool hasAnyFixedPricing,
    bool hasAnyRangePricing,
  ) {
    String partsText = 'Parts: ';
    String labourText = 'Labour: ';

    // Build parts pricing text
    if (partPrice > 0) {
      partsText += 'RM${partPrice.toStringAsFixed(2)}';
      if (partPriceMin > 0 || partPriceMax > 0) {
        partsText +=
            ' (+RM${partPriceMin.toStringAsFixed(2)}-RM${partPriceMax.toStringAsFixed(2)})';
      }
    } else if (partPriceMin > 0 || partPriceMax > 0) {
      partsText +=
          'RM${partPriceMin.toStringAsFixed(2)}-${partPriceMax.toStringAsFixed(2)}';
    } else {
      partsText += 'RM0.00';
    }

    // Build labour pricing text
    if (labourPrice > 0) {
      labourText += 'RM${labourPrice.toStringAsFixed(2)}';
      if (labourPriceMin > 0 || labourPriceMax > 0) {
        labourText +=
            ' (+RM${labourPriceMin.toStringAsFixed(2)}-RM${labourPriceMax.toStringAsFixed(2)})';
      }
    } else if (labourPriceMin > 0 || labourPriceMax > 0) {
      labourText +=
          'RM${labourPriceMin.toStringAsFixed(2)}-${labourPriceMax.toStringAsFixed(2)}';
    } else {
      labourText += 'RM0.00';
    }

    return '$partsText | $labourText';
  }

  Color _getPricingBackgroundColor(bool hasFixedPricing, bool hasRangePricing) {
    if (hasFixedPricing && !hasRangePricing) {
      return AppColors.successColor.withOpacity(0.1);
    } else if (hasRangePricing) {
      return AppColors.warningColor.withOpacity(0.1);
    } else {
      return AppColors.textMuted.withOpacity(0.1);
    }
  }

  Color _getPricingBorderColor(bool hasFixedPricing, bool hasRangePricing) {
    if (hasFixedPricing && !hasRangePricing) {
      return AppColors.successColor.withOpacity(0.3);
    } else if (hasRangePricing) {
      return AppColors.warningColor.withOpacity(0.3);
    } else {
      return AppColors.textMuted.withOpacity(0.3);
    }
  }

  Widget _buildPackageCard(ServicePackage package) {
    final isSelected = selectedPackage?.id == package.id;
    final pricing =
        packagePricing[package.id] ??
        {
          'fixedPrice': 0.0,
          'minPrice': 0.0,
          'maxPrice': 0.0,
          'partPrice': 0.0,
          'labourPrice': 0.0,
          'partPriceMin': 0.0,
          'partPriceMax': 0.0,
          'labourPriceMin': 0.0,
          'labourPriceMax': 0.0,
        };
    final duration = packageDurations[package.id] ?? package.estimatedDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        elevation: isSelected ? 4 : 1,
        shadowColor:
            isSelected
                ? AppColors.primaryColor.withOpacity(0.3)
                : Colors.black.withOpacity(0.1),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              selectedPackage = isSelected ? null : package;
              _calculateTotalPrice();
            });
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isSelected ? AppColors.primaryColor : AppColors.borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.inventory_2,
                        color: AppColors.accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${package.services.length} services included',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? AppColors.primaryColor
                                : AppColors.surfaceColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected ? Icons.check : Icons.add,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  package.description,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      package.services
                          .map(
                            (service) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                service.serviceName,
                                style: TextStyle(
                                  color: AppColors.primaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPackagePriceChip(pricing),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Est: ${duration}min',
                        style: TextStyle(
                          color: AppColors.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPackagePriceChip(Map<String, dynamic> pricing) {
    double fixedPrice = pricing['fixedPrice'] ?? 0.0;
    double minPrice = pricing['minPrice'] ?? 0.0;
    double maxPrice = pricing['maxPrice'] ?? 0.0;

    // Extract part and labor pricing from the package pricing
    double partPrice = pricing['partPrice'] ?? 0.0;
    double labourPrice = pricing['labourPrice'] ?? 0.0;
    double partPriceMin = pricing['partPriceMin'] ?? 0.0;
    double partPriceMax = pricing['partPriceMax'] ?? 0.0;
    double labourPriceMin = pricing['labourPriceMin'] ?? 0.0;
    double labourPriceMax = pricing['labourPriceMax'] ?? 0.0;

    // Check pricing types
    bool hasAnyFixedPricing =
        fixedPrice > 0 || partPrice > 0 || labourPrice > 0;
    bool hasAnyRangePricing =
        minPrice > 0 ||
        maxPrice > 0 ||
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _getPricingBackgroundColor(
          hasAnyFixedPricing,
          hasAnyRangePricing,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getPricingBorderColor(hasAnyFixedPricing, hasAnyRangePricing),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main price display
          if (hasAnyFixedPricing && hasAnyRangePricing && maxPrice > 0)
            Text(
              'RM${(fixedPrice + minPrice).toStringAsFixed(2)} - RM${(fixedPrice + maxPrice).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.warningColor,
              ),
            )
          else if (hasAnyFixedPricing && !hasAnyRangePricing)
            Text(
              'RM${fixedPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.successColor,
              ),
            )
          else if (hasAnyRangePricing && (minPrice > 0 || maxPrice > 0))
            Text(
              'RM${minPrice.toStringAsFixed(2)} - RM${maxPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.warningColor,
              ),
            )
          else
            Text(
              'Quote on request',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textMuted,
              ),
            ),

          const SizedBox(height: 4),

          // Detailed breakdown
          Text(
            _getPackageDetailedPricingBreakdown(
              partPrice,
              labourPrice,
              partPriceMin,
              partPriceMax,
              labourPriceMin,
              labourPriceMax,
              hasAnyFixedPricing,
              hasAnyRangePricing,
            ),
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _getPackageDetailedPricingBreakdown(
    double partPrice,
    double labourPrice,
    double partPriceMin,
    double partPriceMax,
    double labourPriceMin,
    double labourPriceMax,
    bool hasAnyFixedPricing,
    bool hasAnyRangePricing,
  ) {
    String partsText = 'Parts: ';
    String labourText = 'Labour: ';

    // Build parts pricing text
    if (partPrice > 0) {
      partsText += 'RM${partPrice.toStringAsFixed(2)}';
      if (partPriceMin > 0 || partPriceMax > 0) {
        partsText +=
            ' (+RM${partPriceMin.toStringAsFixed(2)}-RM${partPriceMax.toStringAsFixed(2)})';
      }
    } else if (partPriceMin > 0 || partPriceMax > 0) {
      partsText +=
          'RM${partPriceMin.toStringAsFixed(2)}-${partPriceMax.toStringAsFixed(2)}';
    } else {
      partsText += 'RM0.00';
    }

    // Build labour pricing text
    if (labourPrice > 0) {
      labourText += 'RM${labourPrice.toStringAsFixed(2)}';
      if (labourPriceMin > 0 || labourPriceMax > 0) {
        labourText +=
            ' (+RM${labourPriceMin.toStringAsFixed(2)}-RM${labourPriceMax.toStringAsFixed(2)})';
      }
    } else if (labourPriceMin > 0 || labourPriceMax > 0) {
      labourText +=
          'RM${labourPriceMin.toStringAsFixed(2)}-${labourPriceMax.toStringAsFixed(2)}';
    } else {
      labourText += 'RM0.00';
    }

    return '$partsText | $labourText';
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
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPackagesState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 24),
            Text(
              'No Service Packages',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This service center doesn\'t offer service packages. Try individual services instead.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
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

          // Show fixed price if available
          if (totalFixedPrice > 0)
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Base Price',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'RM${totalFixedPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.successColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),

          // Show range price if available
          if (totalRangePrice.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  totalFixedPrice > 0 ? 'Est Additional' : 'Est Total',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  totalRangePrice,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppColors.warningColor,
                  ),
                ),
              ],
            ),

          // Show final total range when both fixed and range exist
          if (totalFixedPrice > 0 && totalRangePrice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.borderColor),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Est Final Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  _calculateFinalTotalRange(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryColor,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                selectionType == 'package'
                    ? 'Package: ${selectedPackage?.name ?? ''}'
                    : 'Services: ${selectedServices.length} selected',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: AppColors.accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${totalEstimatedDuration}min',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to calculate final total range
  String _calculateFinalTotalRange() {
    if (totalFixedPrice > 0 && totalRangePrice.isNotEmpty) {
      // Extract min and max from range string
      final rangeParts = totalRangePrice.replaceAll('RM', '').split(' - ');
      if (rangeParts.length == 2) {
        try {
          double min = double.parse(rangeParts[0]);
          double max = double.parse(rangeParts[1]);
          double finalMin = totalFixedPrice + min;
          double finalMax = totalFixedPrice + max;
          return 'RM${finalMin.toStringAsFixed(2)} - RM${finalMax.toStringAsFixed(2)}';
        } catch (e) {
          return 'RM${totalFixedPrice.toStringAsFixed(2)} + ${totalRangePrice}';
        }
      }
    }
    return totalRangePrice.isNotEmpty
        ? totalRangePrice
        : 'RM${totalFixedPrice.toStringAsFixed(2)}';
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
                child: _buildUrgencyChip(
                  'normal',
                  'Normal',
                  AppColors.successColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildUrgencyChip(
                  'urgent',
                  'Urgent',
                  AppColors.errorColor,
                ),
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
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
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

  Future<void> _showDatePicker() async {
    // Find the first available date starting from tomorrow
    DateTime initialDate = DateTime.now().add(const Duration(days: 1));

    // Find the next available date that's not closed
    for (int i = 0; i < 60; i++) {
      DateTime candidateDate = DateTime.now().add(Duration(days: i + 1));
      if (!_isDateClosed(candidateDate)) {
        initialDate = candidateDate;
        break;
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      selectableDayPredicate: (DateTime date) {
        return !_isDateClosed(date);
      },
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedTime = null;
      });
      await _generateTimeSlotsForDate(picked);
    }
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
            'Choose your preferred date and time (Est: ${_formatDuration(totalEstimatedDuration)})',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
          ),

          // Add multi-day warning if needed
          if (selectedDate != null && _isMultiDayService(selectedDate!)) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warningColor.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.warningColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FutureBuilder<int>(
                      future: _calculateDaysNeeded(selectedDate!),
                      builder: (context, snapshot) {
                        final daysNeeded = snapshot.data ?? 1;
                        return Text(
                          'This service requires $daysNeeded day${daysNeeded > 1 ? 's' : ''} to complete. We will find consecutive available days starting from your selected date.',
                          style: TextStyle(
                            color: AppColors.warningColor,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

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
                  onTap: _showDatePicker,
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
                        Icon(
                          Icons.calendar_today,
                          color: AppColors.primaryColor,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDate != null
                              ? DateFormat(
                            'EEEE, dd MMM yyyy',
                          ).format(selectedDate!)
                              : 'Choose Date',
                          style: TextStyle(
                            fontSize: 16,
                            color:
                            selectedDate != null
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Add multi-day warning if needed
                if (selectedDate != null && _isDateClosed(selectedDate!))
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.errorColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: AppColors.errorColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Service center is closed on this date. Please select another date.',
                            style: TextStyle(
                              color: AppColors.errorColor,
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
                if (loading)
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          selectedDate != null &&
                              _isMultiDayService(selectedDate!)
                              ? 'Finding available time slots...'
                              : 'Finding available time slots...',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (selectedDate == null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Text(
                          'Please select a date first',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (availableTimeSlots.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.errorColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.errorColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            color: AppColors.errorColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedDate != null &&
                                  _isMultiDayService(selectedDate!)
                                  ? 'No consecutive days available starting from this date. Please choose another start date.'
                                  : 'No available time slots for the selected date. Please choose another date.',
                              style: TextStyle(
                                color: AppColors.errorColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Time Slots (${availableTimeSlots.length} slots)',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 2.5,
                          ),
                          itemCount: availableTimeSlots.length,
                          itemBuilder: (context, index) {
                            final slot = availableTimeSlots[index];
                            final isSelected =
                                selectedTime?.hour == slot.hour &&
                                    selectedTime?.minute == slot.minute;

                            return InkWell(
                              onTap: () {
                                setState(() {
                                  selectedTime = slot;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                  isSelected
                                      ? AppColors.primaryColor
                                      : AppColors.surfaceColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                    isSelected
                                        ? AppColors.primaryColor
                                        : AppColors.borderColor,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    slot.format(context),
                                    style: TextStyle(
                                      color:
                                      isSelected
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (selectedTime != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.successColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.successColor.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: AppColors.successColor,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Selected Time Slot',
                                      style: TextStyle(
                                        color: AppColors.successColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _buildServiceSchedulePreview(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
              ],
            ),
          ),

          // Priority and Notes
          const SizedBox(height: 24),
          _buildPrioritySelection(),
          const SizedBox(height: 24),
          _buildNotesSection(),

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
                      Icon(
                        Icons.info_outline,
                        color: AppColors.accentColor,
                        size: 20,
                      ),
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
                  ...widget.serviceCenter.operatingHours.map((hours) {
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

  Widget _buildServiceSchedulePreview() {
    if (selectedTime == null || selectedDate == null) return const SizedBox();

    List<Widget> scheduleDays = [];
    int remainingDuration = totalEstimatedDuration;
    DateTime currentDate = selectedDate!;
    TimeOfDay currentStartTime = selectedTime!;
    int dayCount = 1;

    while (remainingDuration > 0 && dayCount <= 7) {
      // Limit to 7 days for safety
      // Get operating hours for current day
      final dayNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final dayName = dayNames[currentDate.weekday - 1];
      final dayHours = widget.serviceCenter.operatingHours.firstWhere(
            (hours) => hours['day'] == dayName,
        orElse: () => {},
      );

      if (dayHours.isEmpty || dayHours['isClosed'] == true) {
        // Skip closed days
        currentDate = currentDate.add(const Duration(days: 1));
        currentStartTime = const TimeOfDay(
          hour: 9,
          minute: 0,
        ); // Reset to opening time
        continue;
      }

      final openTime = _parseTimeString(dayHours['open'] ?? '09:00');
      final closeTime = _parseTimeString(dayHours['close'] ?? '18:00');

      // Calculate available minutes for this day
      int dayStartMinutes =
      (dayCount == 1)
          ? currentStartTime.hour * 60 + currentStartTime.minute
          : openTime.hour * 60 + openTime.minute;

      int dayEndMinutes = closeTime.hour * 60 + closeTime.minute;
      int availableMinutesToday = dayEndMinutes - dayStartMinutes;

      // Calculate how much time we can use today
      int minutesUsedToday = remainingDuration.clamp(0, availableMinutesToday);

      // Calculate end time for today
      TimeOfDay endTimeToday = TimeOfDay(
        hour: (dayStartMinutes + minutesUsedToday) ~/ 60,
        minute: (dayStartMinutes + minutesUsedToday) % 60,
      );

      // Add schedule entry for this day
      scheduleDays.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Day $dayCount (${DateFormat('EEE, MMM dd').format(currentDate)}): '
                '${_formatTimeOfDay(currentStartTime)} - ${_formatTimeOfDay(endTimeToday)} '
                '(${_formatDuration(minutesUsedToday)})',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      );

      // Update remaining duration and move to next day
      remainingDuration -= minutesUsedToday;

      if (remainingDuration > 0) {
        // Move to next day
        currentDate = currentDate.add(const Duration(days: 1));
        currentStartTime = openTime; // Start at opening time next day
        dayCount++;
      }
    }

    // If there's still remaining duration after 7 days, show a warning
    if (remainingDuration > 0) {
      scheduleDays.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Note: Service requires additional time beyond 7 days',
            style: TextStyle(
              color: AppColors.warningColor,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: scheduleDays,
    );
  }

  // Helper method to format TimeOfDay consistently
  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dateTime = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    return DateFormat('h:mma').format(dateTime).toLowerCase();
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
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
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
                          widget.serviceCenter.images.first,
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
                            return Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.home_repair_service,
                                color: AppColors.textMuted,
                              ),
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
                            '${selectedVehicle?['make']} ${selectedVehicle?['model']}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${selectedVehicle?['year']} • ${selectedVehicle?['plateNumber']}',
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

          // Services/Package Info
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
                  selectionType == 'package'
                      ? 'Selected Package'
                      : 'Selected Services (${selectedServices.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),

                if (selectionType == 'package' && selectedPackage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2,
                              color: AppColors.accentColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              selectedPackage!.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedPackage!.description,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children:
                              selectedPackage!.services
                                  .map(
                                    (service) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryColor
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        service.serviceName,
                                        style: TextStyle(
                                          color: AppColors.primaryColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  ...selectedServices
                      .map(
                        (service) => Container(
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
                                color: _getServiceColor(
                                  service.serviceName ?? '',
                                ),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  service.serviceName ??
                                      service.serviceDescription,
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
                        ),
                      )
                      .toList(),
                ],
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
                          ? DateFormat(
                            'EEEE, MMM dd, yyyy',
                          ).format(selectedDate!)
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
                      selectedTime != null
                          ? '${selectedTime!.format(context)} - ${TimeOfDay(hour: (selectedTime!.hour * 60 + selectedTime!.minute + totalEstimatedDuration) ~/ 60, minute: (selectedTime!.hour * 60 + selectedTime!.minute + totalEstimatedDuration) % 60).format(context)}'
                          : 'Time not selected',
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
                    Icon(Icons.timer_outlined, color: AppColors.accentColor),
                    const SizedBox(width: 12),
                    Text(
                      'Estimated Duration: ${totalEstimatedDuration}min',
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
                      urgencyLevel == 'urgent'
                          ? Icons.priority_high
                          : Icons.schedule,
                      color:
                          urgencyLevel == 'urgent'
                              ? AppColors.errorColor
                              : AppColors.successColor,
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (currentStep > 0) const SizedBox(width: 16),
          Expanded(
            flex: currentStep == 0 ? 1 : 2,
            child: ElevatedButton(
              onPressed:
                  loading || !_canProceed()
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
              child:
                  loading
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
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

  Color _getServiceColor(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('brake')) return AppColors.errorColor;
    if (name.contains('engine')) return Colors.redAccent;
    if (name.contains('oil')) return Colors.orangeAccent;
    if (name.contains('tire') || name.contains('tyre'))
      return Colors.blueAccent;
    if (name.contains('battery')) return Colors.green;
    if (name.contains('air conditioning') || name.contains('ac'))
      return Colors.cyan;
    if (name.contains('transmission')) return Colors.purple;
    if (name.contains('suspension')) return Colors.indigo;
    return AppColors.accentColor;
  }

  IconData _getServiceIcon(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('brake')) return Icons.disc_full;
    if (name.contains('engine')) return Icons.build_circle;
    if (name.contains('oil')) return Icons.local_gas_station;
    if (name.contains('tire') || name.contains('tyre'))
      return Icons.tire_repair;
    if (name.contains('battery')) return Icons.battery_charging_full;
    if (name.contains('air conditioning') || name.contains('ac'))
      return Icons.ac_unit;
    if (name.contains('transmission')) return Icons.settings;
    if (name.contains('suspension')) return Icons.drive_eta;
    if (name.contains('diagnostic')) return Icons.search;
    return Icons.build;
  }
}
