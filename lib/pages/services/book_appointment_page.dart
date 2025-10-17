import 'dart:convert';

import 'package:flutter/material.dart';
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

class BookAppointmentPage extends StatefulWidget {
  final String userId;
  final ServiceCenter serviceCenter;
  final List<ServiceCenterServiceOffer> services;
  final List<ServicePackage> packages;
  final String selectionType;
  final String selectedVehiclePlateNo;
  final int totalEstimatedDuration;
  final double totalFixedPrice;
  final double totalRangePriceMin;
  final double totalRangePriceMax;
  final Map<String, int> packageDurations;
  final Map<String, Map<String, dynamic>> packagePricing;
  final double subtotal;
  final double sst;
  final double totalEstAmount;
  final String subtotalRange;
  final String sstRange;
  final String totalEstAmountRange;
  final bool hasRangePricing;

  const BookAppointmentPage({
    super.key,
    required this.userId,
    required this.serviceCenter,
    required this.services,
    required this.packages,
    required this.selectionType,
    required this.selectedVehiclePlateNo,
    required this.totalEstimatedDuration,
    required this.totalFixedPrice,
    required this.totalRangePriceMin,
    required this.totalRangePriceMax,
    required this.packageDurations,
    required this.packagePricing,
    required this.subtotal,
    required this.sst,
    required this.totalEstAmount,
    required this.hasRangePricing,
    required this.subtotalRange,
    required this.sstRange,
    required this.totalEstAmountRange,
  });

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  final PageController _pageController = PageController();
  String userName = '';
  String userEmail = '';
  final chatClient = StreamChatClient(
    '3mj9hufw92nk',
    logLevel: Level.INFO,
  );
  int currentStep = 0;

  // Form data
  String? selectedVehicleId;
  Map<String, dynamic>? selectedVehicle;
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  String urgencyLevel = 'normal';
  String additionalNotes = 'No additional notes';

  List<Map<String, dynamic>> userVehicles = [];
  List<TimeOfDay> availableTimeSlots = [];
  List<String> blockedDates = [];
  List<String> existingBookings = [];
  bool loading = false;
  bool isServiceCenterOpen = false;
  int get totalEstimatedDuration => widget.totalEstimatedDuration;
  double get totalFixedPrice => widget.totalFixedPrice;
  double get totalRangePriceMin => widget.totalRangePriceMin;
  double get totalRangePriceMax => widget.totalRangePriceMax;

  @override
  void initState() {
    super.initState();
    selectedVehicleId = widget.selectedVehiclePlateNo;
    _loadUserData();
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
          if (selectedVehicleId != null && selectedVehicleId!.isNotEmpty) {
            selectedVehicle = approvedVehicles.firstWhere(
              (v) => v['plateNumber'] == selectedVehicleId,
              orElse:
                  () =>
                      approvedVehicles.isNotEmpty ? approvedVehicles.first : {},
            );
          } else if (approvedVehicles.isNotEmpty) {
            // Fallback to first vehicle
            selectedVehicle = approvedVehicles.first;
            selectedVehicleId = selectedVehicle!['plateNumber'];
          }
          userName = data['name'];
          userEmail = data['email'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
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
      final query = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('scheduledDate', isEqualTo: Timestamp.fromDate(date))
          .where('status', whereIn: [
        'pending', // block pending bookings (no bay assigned yet)
      ])
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

  Future<List<Map<String, dynamic>>> _getAvailableBaysForSlot(
      DateTime date,
      TimeOfDay startTime,
      int duration
      ) async {
    try {
      final baysQuery = await FirebaseFirestore.instance
          .collection('bays')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('active', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> allBays = baysQuery.docs
          .map((doc) => {
        'id': doc.id,
        ...doc.data(),
      })
          .toList();

      if (allBays.isEmpty) {
        return [];
      }

      // Get all bookings that overlap with the requested time slot
      final startDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        startTime.hour,
        startTime.minute,
      );
      final endDateTime = startDateTime.add(Duration(minutes: duration));

      // Only check bookings that are assigned or in progress have bay assignments
      final bookingsQuery = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('scheduledDate', isEqualTo: Timestamp.fromDate(date))
          .where('status', whereIn: ['assigned', 'in_progress', 'invoice_generated'])
          .get();

      // Find which bays are occupied during the requested time
      final Set<String> occupiedBayIds = {};

      for (final bookingDoc in bookingsQuery.docs) {
        final booking = bookingDoc.data();
        final bookingTimeStr = booking['scheduledTime'] as String?;
        final bookingDuration = booking['estimatedDuration'] as int? ?? 60;
        final bayId = booking['bayId'] as String?;

        if (bookingTimeStr != null && bayId != null) {
          final timeParts = bookingTimeStr.split(':');
          final bookingStartTime = TimeOfDay(
            hour: int.parse(timeParts[0]),
            minute: int.parse(timeParts[1]),
          );

          final bookingStartDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            bookingStartTime.hour,
            bookingStartTime.minute,
          );
          final bookingEndDateTime = bookingStartDateTime.add(Duration(minutes: bookingDuration));

          // Check if time slots overlap
          if (startDateTime.isBefore(bookingEndDateTime) &&
              endDateTime.isAfter(bookingStartDateTime)) {
            occupiedBayIds.add(bayId);
          }
        }
      }

      // Return available bays not in occupiedBayIds
      return allBays.where((bay) => !occupiedBayIds.contains(bay['id'])).toList();
    } catch (e) {
      debugPrint('Error getting available bays: $e');
      return [];
    }
  }

  Future<void> _generateTimeSlotsForDate(DateTime date) async {
    setState(() {
      availableTimeSlots.clear();
      loading = true;
    });

    try {
      List<TimeOfDay> slots = [];

      if (_isMultiDayService(date)) {
        // For multi-day services, need to check consecutive days
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

    // Calculate how many days need based on actual operating hours
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

      // Check for pending booking conflicts for this day portion
      final dayPortionDuration = remainingDuration.clamp(0, availableMinutesToday);

      if (dayPortionDuration > 0) {
        // Check if there are pending bookings that conflict
        final pendingConflicts = await _hasPendingBookingConflict(
            checkDate,
            TimeOfDay(hour: dayStartMinutes ~/ 60, minute: dayStartMinutes % 60),
            dayPortionDuration
        );

        if (pendingConflicts) {
          return false;
        }

        // Check bay availability for assigned bookings
        final TimeOfDay dayStartTime = (day == 0)
            ? startTime
            : openTime;

        final availableBays = await _getAvailableBaysForSlot(
            checkDate,
            dayStartTime,
            dayPortionDuration
        );

        if (availableBays.isEmpty) {
          return false; // No available bays for this day portion
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

  Future<bool> _hasPendingBookingConflict(DateTime date, TimeOfDay startTime, int duration) async {
    try {
      final pendingBookings = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('scheduledDate', isEqualTo: Timestamp.fromDate(date))
          .where('status', isEqualTo: 'pending')
          .get();

      final startMinutes = startTime.hour * 60 + startTime.minute;
      final endMinutes = startMinutes + duration;

      for (final doc in pendingBookings.docs) {
        final booking = doc.data();
        final bookingTimeStr = booking['scheduledTime'] as String?;
        final bookingDuration = booking['estimatedDuration'] as int? ?? 60;

        if (bookingTimeStr != null) {
          final timeParts = bookingTimeStr.split(':');
          final bookingStartMinutes = int.parse(timeParts[0]) * 60 + int.parse(timeParts[1]);
          final bookingEndMinutes = bookingStartMinutes + bookingDuration;

          // Check if time slots overlap
          if (startMinutes < bookingEndMinutes && endMinutes > bookingStartMinutes) {
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('Error checking pending conflicts: $e');
      return true;
    }
  }

  Future<List<TimeOfDay>> _findSingleDayTimeSlots(DateTime date) async {
    List<TimeOfDay> slots = [];

    if (_isDateClosed(date)) {
      return slots;
    }

    final serviceCenterHours = await _getServiceCenterHours();
    final occupiedSlots = await _getServiceCenterOccupiedSlots(date);
    final allBays = await _getAllBays();

    // If no bays available at all, return empty slots
    if (allBays.isEmpty) {
      return slots;
    }

    for (
    int hour = serviceCenterHours['openHour']!;
    hour <= serviceCenterHours['closeHour']! - 1;
    hour++
    ) {
      for (int minute = 0; minute < 60; minute += 30) {
        final startTime = TimeOfDay(hour: hour, minute: minute);
        final startMinutes = hour * 60 + minute;
        final endMinutes = startMinutes + totalEstimatedDuration;
        final closeMinutes = serviceCenterHours['closeHour']! * 60;

        // Check if slot fits within operating hours
        if (endMinutes <= closeMinutes) {
          // Check for conflicts with pending bookings
          bool hasPendingConflict = false;
          for (final occupied in occupiedSlots) {
            final occupiedStart = occupied.start.hour * 60 + occupied.start.minute;
            final occupiedEnd = occupied.end.hour * 60 + occupied.end.minute;

            if (startMinutes < occupiedEnd && endMinutes > occupiedStart) {
              hasPendingConflict = true;
              break;
            }
          }

          // If no pending conflicts, check bay availability for assigned bookings
          if (!hasPendingConflict) {
            final availableBays = await _getAvailableBaysForSlot(
                date,
                startTime,
                totalEstimatedDuration
            );

            // Only add slot if there are available bays
            if (availableBays.isNotEmpty) {
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
    }

    return slots;
  }

  Future<List<Map<String, dynamic>>> _getAllBays() async {
    try {
      final baysQuery = await FirebaseFirestore.instance
          .collection('bays')
          .where('serviceCenterId', isEqualTo: widget.serviceCenter.id)
          .where('active', isEqualTo: true)
          .get();

      return baysQuery.docs
          .map((doc) => {
        'id': doc.id,
        ...doc.data(),
      })
          .toList();
    } catch (e) {
      debugPrint('Error getting all bays: $e');
      return [];
    }
  }

  void _nextStep() {
    if (currentStep < 1) {
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
        return selectedDate != null && selectedTime != null;
      case 1:
        return true; // Confirmation step always allowed
      default:
        return false;
    }
  }

  Future<void> _confirmBooking() async {
    if (!_canProceed()) return;

    setState(() => loading = true);

    try {
      // Use the pre-calculated values from widget instead of recalculating
      int totalDuration = widget.totalEstimatedDuration;

      // Determine selection type
      final hasPackages = widget.packages.isNotEmpty;
      final hasServices = widget.services.isNotEmpty;
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
        'estimatedDuration': totalDuration,
        'urgencyLevel': urgencyLevel,
        'additionalNotes': additionalNotes,
        'subtotal': widget.subtotal,
        'subtotalRange': widget.subtotalRange,
        'sstRange': widget.sstRange,
        'sst': widget.sst,
        'totalFixedPrice': widget.totalFixedPrice,
        'totalRangePriceMin': widget.totalRangePriceMin,
        'totalRangePriceMax': widget.totalRangePriceMax,
        'totalEstAmount': widget.totalEstAmount,
        'totalEstAmountRange': widget.totalEstAmountRange,
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

      // Store packages data - USE PRE-CALCULATED VALUES FROM WIDGET
      if (hasPackages) {
        bookingData['packages'] =
            widget.packages.map((package) {
              final packageDuration =
                  widget.packageDurations[package.id] ??
                  package.estimatedDuration;
              final pricing =
                  widget.packagePricing[package.id] ??
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
              return {
                'packageId': package.id,
                'packageName': package.name,
                'description': package.description,
                'estimatedDuration': packageDuration,
                'labourPrice': pricing['totalLabourPrice'] ?? 0.0,
                'labourPriceMin': pricing['minLabourPrice'] ?? 0.0,
                'labourPriceMax': pricing['maxLabourPrice'] ?? 0.0,
                'partPrice': pricing['totalPartPrice'] ?? 0.0,
                'partPriceMin': pricing['minPartPrice'] ?? 0.0,
                'partPriceMax': pricing['maxPartPrice'] ?? 0.0,
                'fixedPrice': fixedPrice,
                'rangePrice':
                    minPrice > 0 && maxPrice > 0
                        ? 'RM${minPrice.toStringAsFixed(2)} - RM${maxPrice.toStringAsFixed(2)}'
                        : '',
                'services':
                    package.services.map((service) {
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
              };
            }).toList();
      }

      // Store individual services data
      if (hasServices) {
        bookingData['services'] =
            widget.services.map((service) {
              return {
                'serviceId': service.serviceId,
                'serviceName':
                    service.serviceName ?? service.serviceDescription,
                'offerId': service.id,
                'duration': service.duration,
                'partPrice': service.partPrice,
                'labourPrice': service.labourPrice,
                'partPriceMin': service.partPriceMin,
                'partPriceMax': service.partPriceMax,
                'labourPriceMin': service.labourPriceMin,
                'labourPriceMax': service.labourPriceMax,
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

          // Update in Firestore
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
          'Book Appointment',
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
                    2,
                    (index) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: index < 1 ? 8 : 0),
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
              children: [_buildDateTimeSelection(), _buildConfirmation()],
            ),
          ),
          _buildBottomNavigation(),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Day $dayCount (${DateFormat('EEE, MMM dd').format(currentDate)}): '
                '${_formatTimeOfDay(currentStartTime)} - ${_formatTimeOfDay(endTimeToday)}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              Text(
                '(${_formatDuration(minutesUsedToday)})',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
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

  Widget _buildPrioritySelection() {
    return Container(
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
        color: AppColors.cardColor,
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
              fillColor: AppColors.surfaceColor,
            ),
            onChanged: (value) => additionalNotes = value,
          ),
        ],
      ),
    );
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
                  child:
                      widget.serviceCenter.serviceCenterPhoto.isNotEmpty
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

                // Service Center Name
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

                // Address
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
                            if (widget.serviceCenter.addressLine2?.isNotEmpty ??
                                false)
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
                      child:
                          (selectedVehicle?['make'] != null && selectedVehicle?['year'] != null)
                              ? Image.network(
                            'https://cdn.imagin.studio/getImage?customer=demo&make=${selectedVehicle?['make']}&modelFamily=${selectedVehicle?['model']}&modelYear=${selectedVehicle?['year']}&angle=01',
                            height: 100,
                                width: 120,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) => Container(
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
                            '•${selectedVehicle?['sizeClass']}}',
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
          _buildInfoCard(
            title: _getSelectionTitle(),
            child: _buildServicesInfo(),
          ),

          const SizedBox(height: 16),

          // Schedule Info
          _buildInfoCard(
            title: 'Schedule',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedTime != null)
                          _buildServiceSchedulePreview()
                        else
                          Text(
                            'Time not selected',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: AppColors.accentColor),
                    const SizedBox(width: 12),
                    Text(
                      'Estimated Duration: ${widget.totalEstimatedDuration}mins',
                      style: TextStyle(
                        fontSize: 14,
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
                        fontSize: 14,
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

                if (widget.packages.isNotEmpty) ...[
                  ...widget.packages
                      .map(
                        (package) =>
                            _buildSelectedPackageItemWithPrice(package),
                      )
                      .toList(),
                ],
                if (widget.services.isNotEmpty) ...[
                  ...widget.services
                      .map(
                        (service) =>
                            _buildSelectedServiceItemWithPrice(service),
                      )
                      .toList(),
                ],

                const SizedBox(height: 16),
                Divider(color: AppColors.borderColor),
                const SizedBox(height: 8),

                // Use the pre-calculated values from widget (these come from SearchServicesPage)
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
                      widget.hasRangePricing
                          ? widget.subtotalRange
                          : 'RM${widget.subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            widget.hasRangePricing
                                ? AppColors.warningColor
                                : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // SST
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SST (8%)',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      widget.hasRangePricing
                          ? widget.sstRange
                          : 'RM${widget.sst.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            widget.hasRangePricing
                                ? AppColors.warningColor
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(color: AppColors.borderColor),
                const SizedBox(height: 8),

                // Final Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Est. Final Total',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.hasRangePricing
                          ? widget.totalEstAmountRange
                          : 'RM${widget.totalEstAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            widget.hasRangePricing
                                ? Colors.redAccent
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
                      _getSelectionSummaryText(),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
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
                            '${widget.totalEstimatedDuration}min',
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
            _buildInfoCard(
              title: 'Additional Notes',
              child: Text(
                additionalNotes,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedServiceItemWithPrice(ServiceCenterServiceOffer service) {
    // Calculate service price using the same logic as SearchServicesPage
    double partPrice = service.partPrice;
    double labourPrice = service.labourPrice;
    double partPriceMin = service.partPriceMin;
    double partPriceMax = service.partPriceMax;
    double labourPriceMin = service.labourPriceMin;
    double labourPriceMax = service.labourPriceMax;

    bool hasFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasRangePricing =
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    String priceText;
    Color priceColor;

    if (hasFixedPricing && hasRangePricing && maxTotal > 0) {
      priceText =
          'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}';
      priceColor = AppColors.warningColor;
    } else if (hasFixedPricing && !hasRangePricing) {
      priceText = 'RM${fixedTotal.toStringAsFixed(2)}';
      priceColor = AppColors.successColor;
    } else if (hasRangePricing && (minTotal > 0 || maxTotal > 0)) {
      priceText =
          'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
      priceColor = AppColors.warningColor;
    } else {
      priceText = 'RM0.00';
      priceColor = AppColors.textMuted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _getServiceColor(
                service.serviceName ?? '',
              ).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _getServiceIcon(service.serviceName ?? ''),
              size: 16,
              color: _getServiceColor(service.serviceName ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.serviceName ?? service.serviceDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${service.duration}min',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            priceText,
            style: TextStyle(
              fontSize: 12,
              color: priceColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPackageItemWithPrice(ServicePackage package) {
    final packageDuration =
        widget.packageDurations[package.id] ?? package.estimatedDuration;
    final pricing =
        widget.packagePricing[package.id] ??
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

    double partPrice = pricing['totalPartPrice'] ?? 0.0;
    double partPriceMin = pricing['minPartPrice'] ?? 0.0;
    double partPriceMax = pricing['maxPartPrice'] ?? 0.0;
    double labourPrice = pricing['totalLabourPrice'] ?? 0.0;
    double labourPriceMin = pricing['minLabourPrice'] ?? 0.0;
    double labourPriceMax = pricing['maxLabourPrice'] ?? 0.0;

    bool hasAnyFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasAnyRangePricing =
        partPriceMin > 0 ||
        partPriceMax > 0 ||
        labourPriceMin > 0 ||
        labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    String priceText;
    Color priceColor;

    if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0) {
      priceText =
          'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}';
      priceColor = AppColors.warningColor;
    } else if (hasAnyFixedPricing && !hasAnyRangePricing) {
      priceText = 'RM${fixedTotal.toStringAsFixed(2)}';
      priceColor = AppColors.successColor;
    } else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0)) {
      priceText =
          'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
      priceColor = AppColors.warningColor;
    } else {
      print(
        'Falling back to quote on request - hasAnyFixedPricing: $hasAnyFixedPricing, hasAnyRangePricing: $hasAnyRangePricing, minTotal: $minTotal, maxTotal: $maxTotal',
      );
      priceText = 'Quote on request';
      priceColor = AppColors.textMuted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.inventory_2,
              size: 16,
              color: AppColors.accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${package.services.length} services',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                priceText,
                style: TextStyle(
                  fontSize: 12,
                  color: priceColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${packageDuration}min',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getSelectionSummaryText() {
    final hasPackages = widget.packages.isNotEmpty;
    final hasServices = widget.services.isNotEmpty;

    if (hasPackages && hasServices) {
      return '${widget.packages.length} package(s) & ${widget.services.length} service(s)';
    } else if (hasPackages) {
      return '${widget.packages.length} package(s)';
    } else if (hasServices) {
      return '${widget.services.length} service(s)';
    } else {
      return 'No services selected';
    }
  }

  Widget _buildSelectedServiceItem(ServiceCenterServiceOffer service) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _getServiceColor(
                service.serviceName ?? '',
              ).withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              _getServiceIcon(service.serviceName ?? ''),
              size: 16,
              color: _getServiceColor(service.serviceName ?? ''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              service.serviceName ?? service.serviceDescription,
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${service.duration}min',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPackageItem(ServicePackage package) {
    final packageDuration =
        widget.packageDurations[package.id] ?? package.estimatedDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.inventory_2,
              size: 16,
              color: AppColors.accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${package.services.length} services',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            '${packageDuration}min',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
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
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPackageInfo() {
    final package = widget.packages.first;
    return Container(
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
              Icon(Icons.inventory_2, color: AppColors.accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  package.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            package.description,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            'Includes ${package.services.length} services:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...package.services
              .map(
                (service) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.successColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          service.serviceName,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  String _getSelectionTitle() {
    final hasPackages = widget.packages.isNotEmpty;
    final hasServices = widget.services.isNotEmpty;

    if (hasPackages && hasServices) {
      return 'Selected Packages & Services (${widget.packages.length + widget.services.length})';
    } else if (hasPackages) {
      return 'Selected Packages (${widget.packages.length})';
    } else if (hasServices) {
      return 'Selected Services (${widget.services.length})';
    } else {
      return 'Selected Services';
    }
  }

  Widget _buildServicesInfo() {
    final hasPackages = widget.packages.isNotEmpty;
    final hasServices = widget.services.isNotEmpty;

    return Column(
      children: [
        // Show packages section
        if (hasPackages) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Packages (${widget.packages.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          ...widget.packages
              .map((package) => _buildPackageItemForConfirmation(package))
              .toList(),
          if (hasServices) const SizedBox(height: 16),
        ],

        // Show services section
        if (hasServices) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Individual Services (${widget.services.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.left,
            ),
          ),
          ...widget.services
              .map((service) => _buildServiceItemForConfirmation(service))
              .toList(),
        ],
      ],
    );
  }

  Widget _buildPackageItemForConfirmation(ServicePackage package) {
    int packageDuration =
        widget.packageDurations[package.id] ?? package.estimatedDuration;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2, color: AppColors.accentColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  package.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Package (${package.services.length} services)',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${packageDuration}min',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceItemForConfirmation(ServiceCenterServiceOffer service) {
    return Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.serviceName ?? service.serviceDescription,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${service.duration}min',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, {Color? color}) {
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
              fontWeight: FontWeight.w300,
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
            flex: 2,
            child: ElevatedButton(
              onPressed:
                  loading || !_canProceed()
                      ? null
                      : (currentStep == 1 ? _confirmBooking : _nextStep),
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
                        currentStep == 2 ? 'Confirm Booking' : 'Continue',
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
