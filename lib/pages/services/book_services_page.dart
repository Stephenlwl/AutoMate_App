import 'dart:convert';

import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'package:automate_application/model/service_center_service_package_offer_model.dart';
import 'package:stream_chat/stream_chat.dart';

import '../../blocs/notification_bloc.dart';
import '../homepage/homepage.dart';

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
  String userName = '';
  String userEmail = '';
  final chatClient = StreamChatClient(
    '3mj9hufw92nk',
    logLevel: Level.INFO,
  );

  int currentStep = 0;
  Map<String, Map<String, dynamic>> offerTiers = {};
  Map<String, Map<String, dynamic>> effectivePricing = {};

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
  String additionalNotes = 'No additional note';

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
  double subTotal = 0.0;
  double sst = 0.08;
  double totalFixedPrice = 0.0;
  double totalRangePriceMin = 0.0;
  double totalRangePriceMax = 0.0;
  bool isServiceCenterOpen = false;
  int totalEstimatedDuration = 0; // in minutes
  bool _showAllServices = false;

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
          userName = data['name'];
          userEmail = data['email'];
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

    return dayHours.isEmpty || dayHours['isClosed'] == true;
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
      'Sunday',
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
              .where(
                'status',
                whereIn: [
                  'pending',
                  'confirmed',
                  'assigned',
                  'in_progress',
                  'ready_to_collect',
                ],
              )
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
        // For multi-day services need to check consecutive days
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

    // Calculate how many days based on actual operating hours
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

    // Check if have enough consecutive available days
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

        // Check if service time conflicts with occupied slot
        if (dayStartMinutes < occupiedEnd &&
            (dayStartMinutes +
                    remainingDuration.clamp(0, availableMinutesToday)) >
                occupiedStart) {
          return false;
        }
      }

      // Deduct the time can use today from remaining duration
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

  // cache category names
  Map<String, String> _categoryNameCache = {};

  // Method to preload all category names
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

        // Check if have compatible offers for this service
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
          {
            'fixedPrice': 0.0,
            'minPrice': 0.0,
            'maxPrice': 0.0,
            'labourPrice': 0.0,
            'labourPriceMin': 0.0,
            'labourPriceMax': 0.0,
            'partPrice': 0.0,
            'partPriceMin': 0.0,
            'partPriceMax': 0.0,
          };
      final duration =
          packageDurations[selectedPackage!.id] ??
          selectedPackage!.estimatedDuration;

      setState(() {
        totalEstimatedDuration = duration;
        totalFixedPrice = pricing['labourPrice'] ?? 0.0;
        if (pricing['minPrice'] != null &&
            pricing['maxPrice'] != null &&
            pricing['minPrice']! > 0 &&
            pricing['maxPrice']! > 0) {
          totalRangePriceMin = pricing['minPrice']!;
          totalRangePriceMax = pricing['maxPrice']!;
        } else {
          totalRangePriceMin = 0.0;
          totalRangePriceMax = 0.0;
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

        // Calculate service totals
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
          // Show both fixed and range
          totalFixedPrice = totalFixed;
          totalRangePriceMin = totalFixed + totalMin;
          totalRangePriceMax = totalFixed + totalMax;
        } else if (hasFixedComponents && !hasRangeComponents) {
          // Only fixed pricing available
          totalFixedPrice = totalFixed;
          totalRangePriceMin = 0.0;
          totalRangePriceMax = 0.0;
        } else if (hasRangeComponents) {
          // Only range pricing available
          totalFixedPrice = 0.0;
          totalRangePriceMin = totalMin;
          totalRangePriceMax = totalMax;
        } else {
          totalFixedPrice = 0.0;
          totalRangePriceMin = 0.0;
          totalRangePriceMax = 0.0;
        }
      });
    } else {
      setState(() {
        totalFixedPrice = 0.0;
        totalRangePriceMin = 0.0;
        totalRangePriceMax = 0.0;
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

      Map<String, dynamic> currentVehicleData = {};
      List<Map<String, dynamic>> currentServiceMaintenances = [];
      int? currentVehicleMileage;

      if (selectedVehicleId != null) {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('car_owners')
                .doc(widget.userId)
                .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          if (userData['vehicles'] != null) {
            final vehicles = List<Map<String, dynamic>>.from(
              userData['vehicles'] as List,
            );

            // Find the selected vehicle
            final selectedVehicle = vehicles.firstWhere(
              (vehicle) => vehicle['plateNumber'] == selectedVehicleId,
              orElse: () => {},
            );

            if (selectedVehicle.isNotEmpty) {
              currentVehicleData = selectedVehicle;
              currentVehicleMileage =
                  selectedVehicle['lastServiceMileage'] as int?;

              // Get service maintenances
              if (selectedVehicle['serviceMaintenances'] != null) {
                currentServiceMaintenances = List<Map<String, dynamic>>.from(
                  selectedVehicle['serviceMaintenances'] as List,
                );
              }
            }
          }
        }
      }

      String subtotalRange = _calculateSubtotalRange();
      String sstRange = _calculateSSTRange(subtotalRange);
      double subtotal = _calculateSubtotal();
      double sst = _calculateSST();
      double finalTotal = _calculateFinalTotal();
      String finalTotalRange = _calculateFinalTotalRange(subtotalRange);

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
        'subtotal': subtotal,
        'subtotalRange': subtotalRange,
        'sstRange': sstRange,
        'sst': sst,
        'totalFixedPrice': totalFixedPrice,
        'totalRangePriceMin': totalRangePriceMin,
        'totalRangePriceMax': totalRangePriceMax,
        'totalEstAmount':finalTotal,
        'totalEstAmountRange': finalTotalRange,
        'currentMileage': currentVehicleMileage ?? 0,
        'serviceMaintenances': currentServiceMaintenances,
        'mileageRecordedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'timestamps': {
          'requestedAt': Timestamp.now(),
          'acceptedAt': null,
          'dispatchedAt': null,
          'driverAssignedAt': null,
          'arrivedAtLocationAt': null,
          'serviceStartedAt': null,
          'completedAt': null,
          'cancelledAt': null,
        },
        'statusHistory': [
          {
            'status': 'pending',
            'timestamp': Timestamp.now(),
            'updatedBy': 'customer',
            'notes': 'Request submitted',
          },
        ],
      };

      // Store packages data
      if (hasPackages && selectedPackage != null) {
        final packageDuration =
            packageDurations[selectedPackage!.id] ??
            selectedPackage!.estimatedDuration;
        final pricing =
            packagePricing[selectedPackage!.id] ??
            {
              'fixedPrice': 0.0,
              'minPrice': 0.0,
              'maxPrice': 0.0,
              'labourPrice': 0.0,
              'labourPriceMin': 0.0,
              'labourPriceMax': 0.0,
              'partPrice': 0.0,
              'partPriceMin': 0.0,
              'partPriceMax': 0.0,
            };

        double fixedPrice = pricing['fixedPrice'] ?? 0.0;
        double minPrice = pricing['minPrice'] ?? 0.0;
        double maxPrice = pricing['maxPrice'] ?? 0.0;

        bookingData['packages'] = [
          {
            'packageId': selectedPackage!.id,
            'packageName': selectedPackage!.name,
            'description': selectedPackage!.description,
            'estimatedDuration': packageDuration,
            'labourPrice': pricing['labourPrice'] ?? 0.0,
            'labourPriceMin': pricing['labourPriceMin'] ?? 0.0,
            'labourPriceMax': pricing['labourPriceMax'] ?? 0.0,
            'partPrice': pricing['partPrice'] ?? 0.0,
            'partPriceMin': pricing['partPriceMin'] ?? 0.0,
            'partPriceMax': pricing['partPriceMax'] ?? 0.0,
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

      final bookingRef = await FirebaseFirestore.instance
          .collection('service_bookings')
          .add(bookingData);

      if (selectedVehicleId != null && currentVehicleData.isNotEmpty) {
        await _updateVehicleLastBooking(selectedVehicleId!, bookingRef.id);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Service booking confirmed successfully! ($selectionType)',
            ),
            backgroundColor: AppColors.successColor,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => Homepage(
                userId: widget.userId,
                chatClient: chatClient,
                userName: userName,
                userEmail: userEmail,
                notificationBloc: context.read<NotificationBloc>(),
            ),
          ),
              (route) => false,
        );
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

  Future<void> _updateVehicleLastBooking(
    String plateNumber,
    String bookingId,
  ) async {
    try {
      final userDoc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        if (userData['vehicles'] != null) {
          final vehicles = List<Map<String, dynamic>>.from(
            userData['vehicles'] as List,
          );

          // Find and update the vehicle
          final updatedVehicles =
              vehicles.map((vehicle) {
                if (vehicle['plateNumber'] == plateNumber) {
                  return {
                    ...vehicle,
                    'lastServiceBookingId': bookingId,
                    'lastServiceBookingAt': Timestamp.now(),
                  };
                }
                return vehicle;
              }).toList();

          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .update({'vehicles': updatedVehicles});
        }
      }
    } catch (e) {
      debugPrint('Error updating vehicle last booking: $e');
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

              final vehicleId = vehicle['plateNumber'] ?? index.toString();

              final isSelected = selectedVehicleId == vehicleId;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: AppColors.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  elevation: isSelected ? 8 : 2,
                  shadowColor:
                      isSelected
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
                      debugPrint(
                        'Selected vehicle: ${vehicle['make']} ${vehicle['model']}',
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              isSelected
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
                              errorBuilder:
                                  (context, error, stackTrace) => Container(
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
                                    color:
                                        isSelected
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
                              color:
                                  isSelected
                                      ? AppColors.primaryColor
                                      : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected
                                        ? AppColors.primaryColor
                                        : AppColors.borderColor,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              isSelected
                                  ? Icons.check
                                  : Icons.radio_button_unchecked,
                              color:
                                  isSelected
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
              Icon(Icons.error_outline, size: 64, color: AppColors.errorColor),
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
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
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

      // Preload all category names
      await _preloadCategoryNames();

      for (var service in services) {
        String categoryName = 'Other Services';

        // First try to get category from service document
        if (service.serviceId.isNotEmpty) {
          try {
            final serviceDoc =
                await FirebaseFirestore.instance
                    .collection('services')
                    .doc(service.serviceId)
                    .get();

            if (serviceDoc.exists) {
              final serviceData = serviceDoc.data()!;
              final categoryId = serviceData['categoryId'] as String?;

              if (categoryId != null && categoryId.isNotEmpty) {
                categoryName =
                    _categoryNameCache[categoryId] ?? 'Other Services';
              }
            }
          } catch (e) {
            debugPrint(
              'Error loading service category for ${service.serviceId}: $e',
            );
          }
        }

        // If still no category found, try direct categoryId from offer
        if (categoryName == 'Other Services' && service.categoryId.isNotEmpty) {
          categoryName =
              _categoryNameCache[service.categoryId] ?? 'Other Services';
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

    // Check pricing types
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
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Text(
                               service.serviceName,
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 12,
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
    bool hasRangePricing = _hasRangePricing();
    double subtotal = _calculateSubtotal();
    double sst = _calculateSST();
    double finalTotal = _calculateFinalTotal();
    String subtotalRange = _calculateSubtotalRange();
    String sstRange = _calculateSSTRange(subtotalRange);
    String finalTotalRange = _calculateFinalTotalRange(subtotalRange);

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
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Price Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // Selected Services/Packages List
          if (selectionType == 'individual' && selectedServices.isNotEmpty) ...[
            ...selectedServices
                .map((service) => _buildSelectedServiceItem(service))
                .toList(),
          ] else if (selectionType == 'package' && selectedPackage != null) ...[
            _buildSelectedPackageItem(),
          ],

          const SizedBox(height: 16),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 8),

          // Subtotal range if any service has range pricing, otherwise fixed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                hasRangePricing
                    ? subtotalRange
                    : 'RM${subtotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color:
                      hasRangePricing
                          ? AppColors.warningColor
                          : AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // SST range if any service has range pricing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SST (8%)',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              Text(
                hasRangePricing ? sstRange : 'RM${sst.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      hasRangePricing
                          ? AppColors.warningColor
                          : AppColors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 8),

          // Final Total - range if any service has range pricing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Est. Final Total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ),
              Text(
                hasRangePricing
                    ? finalTotalRange
                    : 'RM${finalTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      hasRangePricing
                          ? AppColors.warningColor
                          : AppColors.primaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: AppColors.borderColor),
          const SizedBox(height: 12),

          // Summary Info
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

  // Build individual selected service item
  Widget _buildSelectedServiceItem(ServiceCenterServiceOffer service) {
    final pricing = effectivePricing[service.id] ?? {};

    double partPrice = pricing['price'] ?? service.partPrice;
    double labourPrice = pricing['labourPrice'] ?? service.labourPrice;
    double partPriceMin = pricing['priceMin'] ?? service.partPriceMin;
    double partPriceMax = pricing['priceMax'] ?? service.partPriceMax;
    double labourPriceMin = pricing['labourPriceMin'] ?? service.labourPriceMin;
    double labourPriceMax = pricing['labourPriceMax'] ?? service.labourPriceMax;

    bool hasFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasRangePricing =
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Name
          Text(
            service.serviceName ?? service.serviceDescription,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // Pricing Details
          if (hasFixedPricing && hasRangePricing && maxTotal > 0) ...[
            if (labourPrice > 0)
              _buildPriceRow(
                'Labour',
                'RM${labourPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (partPrice > 0)
              _buildPriceRow(
                'Parts',
                'RM${partPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (labourPriceMin > 0 && labourPriceMax > labourPriceMin)
              _buildPriceRow(
                'Labour (Est.)',
                'RM${labourPriceMin.toStringAsFixed(2)} - RM${labourPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (partPriceMin > 0 && partPriceMax > partPriceMin)
              _buildPriceRow(
                'Parts (Est.)',
                'RM${partPriceMin.toStringAsFixed(2)} - RM${partPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if ((fixedTotal + minTotal) > 0)
              _buildPriceRow(
                'Est. Service Total',
                'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
          ] else if (hasFixedPricing && !hasRangePricing) ...[
            if (labourPrice > 0)
              _buildPriceRow(
                'Labour',
                'RM${labourPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (partPrice > 0)
              _buildPriceRow(
                'Parts',
                'RM${partPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (fixedTotal > 0)
              _buildPriceRow(
                'Service Total',
                'RM${fixedTotal.toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
            if (fixedTotal == 0)
              _buildPriceRow('Service Total', 'RM0.00', AppColors.textMuted),
          ] else if (hasRangePricing && (minTotal > 0 || maxTotal > 0)) ...[
            if (labourPriceMin > 0 && labourPriceMax > labourPriceMin)
              _buildPriceRow(
                'Labour (Est.)',
                'RM${labourPriceMin.toStringAsFixed(2)} - RM${labourPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (partPriceMin > 0 && partPriceMax > partPriceMin)
              _buildPriceRow(
                'Parts (Est.)',
                'RM${partPriceMin.toStringAsFixed(2)} - RM${partPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (minTotal > 0 && maxTotal > minTotal)
              _buildPriceRow(
                'Est. Service Total',
                'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
            if (minTotal == 0 && maxTotal == 0)
              _buildPriceRow('Service Total', 'RM0.00', AppColors.textMuted),
          ] else ...[
            _buildPriceRow('Service Total', 'RM0.00', AppColors.textMuted),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedPackageItem() {
    final pricing = packagePricing[selectedPackage!.id] ?? {};

    double partPrice = pricing['partPrice'] ?? 0.0;
    double labourPrice = pricing['labourPrice'] ?? 0.0;
    double partPriceMin = pricing['partPriceMin'] ?? 0.0;
    double partPriceMax = pricing['partPriceMax'] ?? 0.0;
    double labourPriceMin = pricing['labourPriceMin'] ?? 0.0;
    double labourPriceMax = pricing['labourPriceMax'] ?? 0.0;

    bool hasFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasRangePricing =
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Package Name
          Text(
            selectedPackage!.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // Package Services Count
          Text(
            'Includes ${selectedPackage!.services.length} services',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),

          // Pricing Details
          if (hasFixedPricing && hasRangePricing && maxTotal > 0) ...[
            if (labourPrice > 0)
              _buildPriceRow(
                'Labour',
                'RM${labourPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (partPrice > 0)
              _buildPriceRow(
                'Parts',
                'RM${partPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (labourPriceMin > 0 && labourPriceMax > labourPriceMin)
              _buildPriceRow(
                'Labour (Est.)',
                'RM${labourPriceMin.toStringAsFixed(2)} - RM${labourPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (partPriceMin > 0 && partPriceMax > partPriceMin)
              _buildPriceRow(
                'Parts (Est.)',
                'RM${partPriceMin.toStringAsFixed(2)} - RM${partPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if ((fixedTotal + minTotal) > 0)
              _buildPriceRow(
                'Est. Package Total',
                'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
          ] else if (hasFixedPricing && !hasRangePricing) ...[
            if (labourPrice > 0)
              _buildPriceRow(
                'Labour',
                'RM${labourPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (partPrice > 0)
              _buildPriceRow(
                'Parts',
                'RM${partPrice.toStringAsFixed(2)}',
                AppColors.successColor,
              ),
            if (fixedTotal > 0)
              _buildPriceRow(
                'Package Total',
                'RM${fixedTotal.toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
            if (fixedTotal == 0)
              _buildPriceRow('Package Total', 'RM0.00', AppColors.textMuted),
          ] else if (hasRangePricing && (minTotal > 0 || maxTotal > 0)) ...[
            if (labourPriceMin > 0 && labourPriceMax > labourPriceMin)
              _buildPriceRow(
                'Labour (Est.)',
                'RM${labourPriceMin.toStringAsFixed(2)} - RM${labourPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (partPriceMin > 0 && partPriceMax > partPriceMin)
              _buildPriceRow(
                'Parts (Est.)',
                'RM${partPriceMin.toStringAsFixed(2)} - RM${partPriceMax.toStringAsFixed(2)}',
                AppColors.warningColor,
              ),
            if (minTotal > 0 && maxTotal > minTotal)
              _buildPriceRow(
                'Est. Package Total',
                'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                AppColors.primaryColor,
              ),
            if (minTotal == 0 && maxTotal == 0)
              _buildPriceRow('Package Total', 'RM0.00', AppColors.textMuted),
          ] else ...[
            _buildPriceRow('Package Total', 'RM0.00', AppColors.textMuted),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value, Color color,
      {bool isBold = false, bool isLarge = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isLarge ? 14 : 12,
            fontWeight: isBold ? FontWeight.w500 : FontWeight.normal,
            color: isLarge ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isLarge ? 14 : 12,
            fontWeight: isBold ? FontWeight.w500 : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  double _calculateSubtotal() {
    double subtotal = 0.0;

    if (selectionType == 'package' && selectedPackage != null) {
      final pricing = packagePricing[selectedPackage!.id] ?? {};
      subtotal = _calculatePackageSubtotal(pricing);
    } else if (selectionType == 'individual' && selectedServices.isNotEmpty) {
      for (final service in selectedServices) {
        final pricing = effectivePricing[service.id] ?? {};
        subtotal += _calculateServiceSubtotal(pricing, service);
      }
    }

    return subtotal;
  }

  double _calculatePackageSubtotal(Map<String, dynamic> pricing) {
    double labour = pricing['labourPrice'] ?? 0.0;
    double parts = pricing['partPrice'] ?? 0.0;
    double labourMin = pricing['labourPriceMin'] ?? 0.0;
    double labourMax = pricing['labourPriceMax'] ?? 0.0;
    double partsMin = pricing['partPriceMin'] ?? 0.0;
    double partsMax = pricing['partPriceMax'] ?? 0.0;

    bool hasFixedLabour = labour > 0;
    bool hasFixedParts = parts > 0;
    bool hasRangeLabour = labourMin > 0 && labourMax > 0;
    bool hasRangeParts = partsMin > 0 && partsMax > 0;

    // Calculate base subtotal using fixed prices when available, otherwise use range min
    double baseLabour = hasFixedLabour ? labour : labourMin;
    double baseParts = hasFixedParts ? parts : partsMin;

    return baseLabour + baseParts;
  }

  double _calculateServiceSubtotal(
    Map<String, dynamic> pricing,
    ServiceCenterServiceOffer service,
  ) {
    double labour = pricing['labourPrice'] ?? service.labourPrice;
    double parts = pricing['price'] ?? service.partPrice;
    double labourMin = pricing['labourPriceMin'] ?? service.labourPriceMin;
    double labourMax = pricing['labourPriceMax'] ?? service.labourPriceMax;
    double partsMin = pricing['priceMin'] ?? service.partPriceMin;
    double partsMax = pricing['priceMax'] ?? service.partPriceMax;

    bool hasFixedLabour = labour > 0;
    bool hasFixedParts = parts > 0;
    bool hasRangeLabour = labourMin > 0 && labourMax > 0;
    bool hasRangeParts = partsMin > 0 && partsMax > 0;

    // Calculate base subtotal using fixed prices when available, otherwise use range min
    double baseLabour = hasFixedLabour ? labour : labourMin;
    double baseParts = hasFixedParts ? parts : partsMin;

    return baseLabour + baseParts;
  }

  // Check if any service/package has range pricing
  bool _hasRangePricing() {
    if (selectionType == 'package' && selectedPackage != null) {
      final pricing = packagePricing[selectedPackage!.id] ?? {};
      return _packageHasRangePricing(pricing);
    } else if (selectionType == 'individual' && selectedServices.isNotEmpty) {
      for (final service in selectedServices) {
        final pricing = effectivePricing[service.id] ?? {};
        if (_serviceHasRangePricing(pricing, service)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _packageHasRangePricing(Map<String, dynamic> pricing) {
    double labourMin = pricing['labourPriceMin'] ?? 0.0;
    double labourMax = pricing['labourPriceMax'] ?? 0.0;
    double partsMin = pricing['partPriceMin'] ?? 0.0;
    double partsMax = pricing['partPriceMax'] ?? 0.0;

    return (labourMin > 0 && labourMax > labourMin) ||
        (partsMin > 0 && partsMax > partsMin);
  }

  bool _serviceHasRangePricing(
    Map<String, dynamic> pricing,
    ServiceCenterServiceOffer service,
  ) {
    double labourMin = pricing['labourPriceMin'] ?? service.labourPriceMin;
    double labourMax = pricing['labourPriceMax'] ?? service.labourPriceMax;
    double partsMin = pricing['priceMin'] ?? service.partPriceMin;
    double partsMax = pricing['priceMax'] ?? service.partPriceMax;

    return (labourMin > 0 && labourMax > labourMin) ||
        (partsMin > 0 && partsMax > partsMin);
  }

  // Calculate subtotal range
  String _calculateSubtotalRange() {
    if (selectionType == 'package' && selectedPackage != null) {
      final pricing = packagePricing[selectedPackage!.id] ?? {};
      return _calculatePackageSubtotalRange(pricing);
    } else if (selectionType == 'individual' && selectedServices.isNotEmpty) {
      return _calculateIndividualServicesSubtotalRange();
    }
    return '';
  }

  String _calculatePackageSubtotalRange(Map<String, dynamic> pricing) {
    double labour = pricing['labourPrice'] ?? 0.0;
    double parts = pricing['partPrice'] ?? 0.0;
    double labourMin = pricing['labourPriceMin'] ?? 0.0;
    double labourMax = pricing['labourPriceMax'] ?? 0.0;
    double partsMin = pricing['partPriceMin'] ?? 0.0;
    double partsMax = pricing['partPriceMax'] ?? 0.0;

    bool hasFixedLabour = labour > 0;
    bool hasFixedParts = parts > 0;
    bool hasRangeLabour = labourMin > 0 && labourMax > labourMin;
    bool hasRangeParts = partsMin > 0 && partsMax > partsMin;

    double minTotal =
        (hasFixedLabour ? labour : labourMin) +
        (hasFixedParts ? parts : partsMin);
    double maxTotal =
        (hasFixedLabour ? labour : labourMax) +
        (hasFixedParts ? parts : partsMax);

    // If there's any range pricing, return the full range
    if (hasRangeLabour || hasRangeParts) {
      return 'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
    }

    return '';
  }

  String _calculateIndividualServicesSubtotalRange() {
    double totalMin = 0.0;
    double totalMax = 0.0;
    bool hasAnyRange = false;

    for (final service in selectedServices) {
      final pricing = effectivePricing[service.id] ?? {};

      double labour = pricing['labourPrice'] ?? service.labourPrice;
      double parts = pricing['price'] ?? service.partPrice;
      double labourMin = pricing['labourPriceMin'] ?? service.labourPriceMin;
      double labourMax = pricing['labourPriceMax'] ?? service.labourPriceMax;
      double partsMin = pricing['priceMin'] ?? service.partPriceMin;
      double partsMax = pricing['priceMax'] ?? service.partPriceMax;

      bool hasFixedLabour = labour > 0;
      bool hasFixedParts = parts > 0;
      bool hasRangeLabour = labourMin > 0 && labourMax > labourMin;
      bool hasRangeParts = partsMin > 0 && partsMax > partsMin;

      // Track if any service has range pricing
      if (hasRangeLabour || hasRangeParts) {
        hasAnyRange = true;
      }

      totalMin +=
          (hasFixedLabour ? labour : labourMin) +
          (hasFixedParts ? parts : partsMin);
      totalMax +=
          (hasFixedLabour ? labour : labourMax) +
          (hasFixedParts ? parts : partsMax);
    }

    if (hasAnyRange && totalMax > totalMin) {
      return 'RM${totalMin.toStringAsFixed(2)} - RM${totalMax.toStringAsFixed(2)}';
    }

    return '';
  }

  String _calculateSSTRange(String subtotalRange) {
    if (subtotalRange.isEmpty) return '';

    double minSubtotal = _extractRangeMin(subtotalRange);
    double maxSubtotal = _extractRangeMax(subtotalRange);

    double minSST = minSubtotal * 0.08;
    double maxSST = maxSubtotal * 0.08;

    return 'RM${minSST.toStringAsFixed(2)} - RM${maxSST.toStringAsFixed(2)}';
  }

  String _calculateFinalTotalRange(String subtotalRange) {
    if (subtotalRange.isEmpty) return '';

    double minSubtotal = _extractRangeMin(subtotalRange);
    double maxSubtotal = _extractRangeMax(subtotalRange);

    double minSST = minSubtotal * 0.08;
    double maxSST = maxSubtotal * 0.08;

    double minTotal = minSubtotal + minSST;
    double maxTotal = maxSubtotal + maxSST;

    return 'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
  }

  double _extractRangeMin(String range) {
    try {
      final parts = range.split(' - ');
      if (parts.length == 2) {
        return double.parse(parts[0].replaceAll('RM', ''));
      }
    } catch (e) {
      debugPrint('Error parsing range min: $e');
    }
    return 0.0;
  }

  double _extractRangeMax(String range) {
    try {
      final parts = range.split(' - ');
      if (parts.length == 2) {
        return double.parse(parts[1].replaceAll('RM', ''));
      }
    } catch (e) {
      debugPrint('Error parsing range max: $e');
    }
    return 0.0;
  }

  double _calculateSST() {
    return _calculateSubtotal() * 0.08;
  }

  double _calculateFinalTotal() {
    return _calculateSubtotal() + _calculateSST();
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
      // Limit to 7 days for safety and get operating hours for current day
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

      // Calculate how much time can use today
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

  Widget _buildServiceImage(String imageStr, {double width = 60, double height = 60}) {
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
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
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
      child: Icon(
        Icons.business_rounded,
        size: 24,
        color: AppColors.textMuted,
      ),
    );
  }

  Widget _buildConfirmation() {
    bool hasRangePricing = _hasRangePricing();
    double subtotal = _calculateSubtotal();
    double sst = _calculateSST();
    double finalTotal = _calculateFinalTotal();
    String subtotalRange = _calculateSubtotalRange();
    String sstRange = _calculateSSTRange(subtotalRange);
    String finalTotalRange = _calculateFinalTotalRange(subtotalRange);

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
              children: [
                // Service Center Image
                Container(
                  width: 300,
                  height: 100,
                  child: widget.serviceCenter.serviceCenterPhoto.isNotEmpty
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildServiceImage(
                      widget.serviceCenter.serviceCenterPhoto,
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
                const SizedBox(height: 16),
                Text(
                  widget.serviceCenter.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.serviceCenter.addressLine1.isNotEmpty)
                              Text(
                                widget.serviceCenter.addressLine1,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            if (widget.serviceCenter.addressLine2?.isNotEmpty ?? false)
                              Text(
                                widget.serviceCenter.addressLine2!,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            Text(
                              '${widget.serviceCenter.postalCode} ${widget.serviceCenter.city}, ${widget.serviceCenter.state}',
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
                  'Selected Vehicle Info',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: (selectedVehicle?['make'] != null && selectedVehicle?['year'] != null)
                          ? Image.network(
                        'https://cdn.imagin.studio/getImage?customer=demo&make=${selectedVehicle?['make']}&modelFamily=${selectedVehicle?['model']}&modelYear=${selectedVehicle?['year']}&angle=01',
                        height: 100,
                        width: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 60,
                          width: 60,
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
                      )
                          : Container(
                        height: 60,
                        width: 60,
                        decoration: BoxDecoration(
                          color: AppColors.cardColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${selectedVehicle?['make']} ${selectedVehicle?['model']} (${selectedVehicle?['year']})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• ${selectedVehicle?['plateNumber']}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• ${selectedVehicle?['sizeClass'] ?? 'N/A'}',
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

                if (selectionType == 'package' && selectedPackage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceColor,
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
                            Expanded(
                              child: Text(
                                selectedPackage!.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildServiceLabels(),
                      ],
                    ),
                  )
                else
                  Column(
                    children: selectedServices
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
                      ),
                    )
                        .toList(),
                  ),
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
                _buildScheduleDetailRow(
                  Icons.calendar_today,
                  selectedDate != null
                      ? DateFormat('EEEE, MMM dd, yyyy').format(selectedDate!)
                      : 'Date not selected',
                ),
                const SizedBox(height: 12),
                if (selectedTime != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildServiceSchedulePreview(),
                    ],
                  )
                else
                  _buildScheduleDetailRow(
                    Icons.access_time,
                    'Time not selected',
                  ),
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  Icons.timer_outlined,
                  'Estimated Duration: ${totalEstimatedDuration}mins',
                ),
                const SizedBox(height: 12),
                _buildScheduleDetailRow(
                  urgencyLevel == 'urgent' ? Icons.priority_high : Icons.schedule,
                  'Priority: ${urgencyLevel.toUpperCase()}',
                  color: urgencyLevel == 'urgent' ? AppColors.errorColor : AppColors.successColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Price Summary
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Price Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),

                // Selected Services/Packages List
                if (selectionType == 'individual' && selectedServices.isNotEmpty)
                  Column(
                    children: selectedServices
                        .map((service) => _buildSelectedServiceItem(service))
                        .toList(),
                  )
                else if (selectionType == 'package' && selectedPackage != null)
                  _buildSelectedPackageItem(),

                const SizedBox(height: 16),
                Divider(color: AppColors.borderColor),
                const SizedBox(height: 8),

                // Pricing rows
                _buildPriceRow(
                  'Subtotal',
                  hasRangePricing ? subtotalRange : 'RM${subtotal.toStringAsFixed(2)}',
                  hasRangePricing ? AppColors.warningColor : AppColors.textPrimary,
                  isBold: true,
                ),
                const SizedBox(height: 8),
                _buildPriceRow(
                  'SST (8%)',
                  hasRangePricing ? sstRange : 'RM${sst.toStringAsFixed(2)}',
                  hasRangePricing ? AppColors.warningColor : AppColors.textSecondary,
                ),
                const SizedBox(height: 12),
                Divider(color: AppColors.borderColor),
                const SizedBox(height: 8),
                _buildPriceRow(
                  'Est. Final Total',
                  hasRangePricing ? finalTotalRange : 'RM${finalTotal.toStringAsFixed(2)}',
                  AppColors.primaryColor,
                  isBold: true,
                  isLarge: true,
                ),

                const SizedBox(height: 16),
                Divider(color: AppColors.borderColor),
                const SizedBox(height: 12),

                // Summary Info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectionType == 'package'
                          ? 'Package: ${selectedPackage?.name ?? ''}'
                          : 'Services: ${selectedServices.length} selected',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
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

  Widget _buildScheduleDetailRow(IconData icon, String text, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? AppColors.accentColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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

  Widget _buildServiceLabels() {
    final services = selectedPackage!.services;
    final displayServices = _showAllServices ? services : services.take(3).toList();
    final hasMoreServices = services.length > 3;
    final remainingCount = services.length - 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Services Included',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${services.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Services Grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: displayServices.map((service) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              service.serviceName,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 12,
              ),
            ),
          )).toList(),
        ),

        if (hasMoreServices) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                _showAllServices = !_showAllServices;
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderColor,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _showAllServices ? 'Collapse Services' : 'View All Services',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 300),
                      turns: _showAllServices ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

}
