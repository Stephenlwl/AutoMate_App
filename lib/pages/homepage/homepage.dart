import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:automate_application/pages/chat/message_chat_list_page.dart';
import 'package:automate_application/pages/chat/customer_support_chat_page.dart';
import 'package:automate_application/services/chat_service.dart';
import 'package:automate_application/pages/towing/request_towing_page.dart';
import 'package:automate_application/pages/service_history/service_hisotry_page.dart';
import 'package:automate_application/pages/my_vehicles/my_vehicles_page.dart';
import 'package:automate_application/pages/notification/notification.dart';
import '../../services/notification_listener_service.dart';
import '../../widgets/notification_badge.dart';
import '../../services/notification_service.dart';
import '../../blocs/notification_bloc.dart';
import '../../pages/towing/towing_request_tracking_page.dart';
import '../../pages/services/service_appointment_tracking_page.dart';
import '../../pages/profile/profile_page.dart';

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

class Homepage extends StatefulWidget {
  final String userId;
  final StreamChatClient chatClient;
  final String userName;
  final String userEmail;
  final NotificationBloc notificationBloc;
  const Homepage({
    super.key,
    required this.userId,
    required this.chatClient,
    required this.userName,
    required this.userEmail,
    required this.notificationBloc,
  });

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  StreamSubscription? _appointmentSubscription;
  StreamSubscription? _towingSubscription;
  StreamSubscription? _vehicleSubscription;
  final ChatService _chatService = ChatService();
  bool _chatInitialized = false;
  bool _isInitializingChat = false;
  String? _chatError;

  int _selectedIndex = 1;

  // Owner Info
  String? ownerName, ownerEmail, ownerPhone;

  // Vehicle Info
  String? plateNumber, make, model, year;
  String? fuelType, displacement, sizeClass;
  int? currentMileage;
  List<Map<String, dynamic>> serviceMaintenances = [];
  List<Map<String, dynamic>> allVehicles = [];
  Map<String, dynamic>? currentVehicle;
  int currentVehicleIndex = 0;

  // Appointment, Payment, Review
  String? apptStatus,
      apptDateStr,
      apptCenterName,
      apptServiceType,
      apptRequestId,
      apptDuration,
      apptUrgency,
      apptVehicleInfo,
      apptAmountFix,
      apptAmountRange;
  num? paymentAmount;
  String? paymentStatus, paymentDueStr;
  double? reviewRating;
  String? reviewComment, reviewCenterName;

  String? towingStatus,
      towingRequestId,
      towingServiceCenterName,
      towingVehicleInfo,
      towingDateStr;
  Timestamp? towingCreatedAt;
  double? towingEstimatedCost;

  final Set<String> _shownReminderIds = {};
  bool _remindersChecked = false;
  int _unreadNotificationCount = 0;
  late NotificationBloc _notificationBloc;
  StreamSubscription? _notificationSubscription;
  String? currentLocation;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _notificationBloc = context.read<NotificationBloc>();
    _initializeNotificationService();
    _initializeChat();
    _loadAll();
    _loadShownReminders();
    _initializeRealTimeListeners();
  }

  void _initializeNotificationService() {
    // Initialize the notification service with the bloc
    final notificationService = NotificationService();
    notificationService.initialize(
      _notificationBloc!,
      userId: widget.userId,
      userName: widget.userName,
      userEmail: widget.userEmail,
    );

    // Listen for notification state changes
    _notificationSubscription = _notificationBloc.stream.distinct().listen((state) {
      if (mounted) {
        final userUnreadCount = state.notifications
            .where((notification) =>
        notification.userId == widget.userId &&
            !notification.isRead)
            .length;

        if (userUnreadCount != _unreadNotificationCount) {
          setState(() {
            _unreadNotificationCount = userUnreadCount;
          });
        }
      }
    });

    // Load initial notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationBloc.add(LoadNotificationsEvent());
    });
  }

  void _initializeRealTimeListeners() {
    _listenToAppointmentUpdates();
    _listenToTowingRequestUpdates();
    _listenToVehicleUpdates();
  }

  void _listenToAppointmentUpdates() {
    final userId = widget.userId;

    FirebaseFirestore.instance
        .collection('service_bookings')
        .where('userId', isEqualTo: userId)
        .where('scheduledDate', isGreaterThanOrEqualTo: DateTime.now())
        .orderBy('scheduledDate', descending: false)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final apptDoc = snapshot.docs.first;
            final apptData = apptDoc.data();

            if (mounted) {
              setState(() {
                apptStatus = apptData['status'];
                apptServiceType =
                    apptData['selectionType'] ?? 'General Service';
                apptRequestId = apptDoc.id;
              });
            }

            _processAppointmentData(apptDoc);
          } else {
            if (mounted) {
              setState(() {
                apptStatus = null;
                apptRequestId = null;
                apptServiceType = null;
                apptDateStr = null;
                apptCenterName = null;
              });
            }
          }
        });
  }

  void _listenToTowingRequestUpdates() {
    final userId = widget.userId;

    FirebaseFirestore.instance
        .collection('towing_requests')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isNotEmpty) {
            final towingDoc = snapshot.docs.first;
            final towingData = towingDoc.data();

            if (mounted) {
              setState(() {
                towingRequestId = towingDoc.id;
                towingStatus = towingData['status'];
                towingCreatedAt = towingData['createdAt'];
                towingEstimatedCost = towingData['estimatedCost']?.toDouble();
              });
            }

            _processTowingData(towingDoc);
          } else {
            if (mounted) {
              setState(() {
                towingStatus = null;
                towingRequestId = null;
                towingServiceCenterName = null;
                towingVehicleInfo = null;
                towingDateStr = null;
              });
            }
          }
        });
  }

  void _listenToVehicleUpdates() {
    final userId = widget.userId;

    FirebaseFirestore.instance
        .collection('car_owners')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data()!;

            if (mounted) {
              setState(() {
                ownerName = data['name'] as String? ?? 'User';
                ownerEmail = data['email'] as String?;
                ownerPhone = data['phone'] as String?;
              });
            }

            if (data['vehicles'] != null) {
              final updatedVehicles = List<Map<String, dynamic>>.from(
                data['vehicles'] as List,
              );

              if (mounted) {
                setState(() {
                  allVehicles = updatedVehicles;
                });
              }

              if (allVehicles.isNotEmpty) {
                final newCurrentVehicleIndex = allVehicles.indexWhere(
                  (vehicle) => vehicle['isDefault'] == true,
                );

                if (newCurrentVehicleIndex == -1 && allVehicles.isNotEmpty) {
                  _updateCurrentVehicle(0);
                } else if (newCurrentVehicleIndex != -1 &&
                    newCurrentVehicleIndex != currentVehicleIndex) {
                  _updateCurrentVehicle(newCurrentVehicleIndex);
                } else {
                  // Refresh current vehicle data
                  _updateCurrentVehicle(currentVehicleIndex);
                }

                // Check reminders after vehicle update
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _checkServiceReminders();
                });
              }
            }
          }
        });
  }

  void _processAppointmentData(
    QueryDocumentSnapshot<Map<String, dynamic>> apptDoc,
  ) async {
    final apptData = apptDoc.data();

    // Get service maintenances from booking
    final bookingServiceMaintenances = apptData['serviceMaintenances'] as List?;
    if (bookingServiceMaintenances != null) {
      final upcomingServices =
          bookingServiceMaintenances
              .map((maintenance) {
                return maintenance['serviceType']?.toString().replaceAll(
                      '_',
                      ' ',
                    ) ??
                    '';
              })
              .where((service) => service.isNotEmpty)
              .toList();

      if (upcomingServices.isNotEmpty) {
        final newServiceType = upcomingServices.take(2).join(', ');
        if (upcomingServices.length > 2) {
          apptServiceType =
              '$newServiceType +${upcomingServices.length - 2} more';
        } else {
          apptServiceType = newServiceType;
        }
      }
    }

    // Get services array for display
    final services = apptData['services'] as List?;
    if (services != null && services.isNotEmpty) {
      final serviceNames =
          services
              .map((service) {
                return service['serviceName']?.toString() ?? '';
              })
              .where((name) => name.isNotEmpty)
              .toList();

      if (serviceNames.isNotEmpty) {
        final newServiceType = serviceNames.take(2).join(', ');
        if (serviceNames.length > 2) {
          apptServiceType = '$newServiceType +${serviceNames.length - 2} more';
        } else {
          apptServiceType = newServiceType;
        }
      }
    }

    // Get preferred date and time
    final scheduledDate = apptData['scheduledDate'] as Timestamp?;
    final scheduledTime = apptData['scheduledTime'] as String?;

    if (scheduledDate != null) {
      final date = scheduledDate.toDate();
      final timeStr = scheduledTime ?? '00:00';
      apptDateStr = '${date.day}/${date.month}/${date.year} $timeStr';
    }

    // Get estimated duration
    final estimatedDuration = apptData['estimatedDuration'] as int?;
    if (estimatedDuration != null) {
      apptDuration = '${estimatedDuration} mins';
    }

    // Get urgency level
    final urgencyLevel = apptData['urgencyLevel'] as String?;
    if (urgencyLevel != null) {
      apptUrgency = urgencyLevel;
    }

    // Get vehicle info
    final vehicleInfo = apptData['vehicle'];
    if (vehicleInfo != null) {
      apptVehicleInfo =
          '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''} ${vehicleInfo['plateNumber'] ?? ''}'
              .trim();
    }

    // Get service center name
    final serviceCenterId = apptData['serviceCenterId'];
    if (serviceCenterId != null) {
      final scQuerySnapshot =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(serviceCenterId)
              .get();

      if (scQuerySnapshot.exists) {
        final scData = scQuerySnapshot.data()!;
        if (mounted) {
          setState(() {
            apptCenterName =
                scData['name'] ??
                scData['serviceCenterInfo']?['name'] ??
                'Service Center';
          });
        }
      }
    }

    // Get total amount if available
    final totalEstAmount = apptData['totalEstAmount'] as num?;
    final totalEstAmountRange = apptData['totalEstAmountRange'];

    if (totalEstAmountRange != null && totalEstAmountRange.isNotEmpty) {
      if (mounted) {
        setState(() {
          apptAmountRange = totalEstAmountRange;
        });
      }
    } else if (totalEstAmount != null && totalEstAmount > 0) {
      if (mounted) {
        setState(() {
          apptAmountFix = 'RM ${totalEstAmount.toStringAsFixed(2)}';
        });
      }
    }
  }

  void _processTowingData(
    QueryDocumentSnapshot<Map<String, dynamic>> towingDoc,
  ) async {
    final towingData = towingDoc.data();

    // Format date
    if (towingCreatedAt != null) {
      final date = towingCreatedAt!.toDate();
      towingDateStr =
          '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }

    // Get vehicle info
    final vehicleInfo = towingData['vehicleInfo'];
    if (vehicleInfo != null) {
      if (mounted) {
        setState(() {
          towingVehicleInfo =
              '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''} ${vehicleInfo['plateNumber'] ?? ''}'
                  .trim();
        });
      }
    }

    // Get service center name
    final serviceCenterId = towingData['serviceCenterId'];
    if (serviceCenterId != null) {
      final scQuerySnapshot =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(serviceCenterId)
              .get();

      if (scQuerySnapshot.exists) {
        final scData = scQuerySnapshot.data()!;
        if (mounted) {
          setState(() {
            towingServiceCenterName =
                scData['name'] ??
                scData['serviceCenterInfo']?['name'] ??
                'Service Center';
          });
        }
      }
    }
  }

  Future<void> _loadShownReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIds =
          prefs.getStringList('shown_reminders_${widget.userId}') ?? [];
      _shownReminderIds.addAll(savedIds);
    } catch (e) {
      debugPrint('Error loading shown reminders: $e');
    }
  }

  // Save shown reminders to SharedPreferences
  Future<void> _saveShownReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'shown_reminders_${widget.userId}',
        _shownReminderIds.toList(),
      );
    } catch (e) {
      debugPrint('Error saving shown reminders: $e');
    }
  }

  // Generate a unique ID for each reminder
  String _generateReminderId(Map<String, dynamic> maintenance) {
    final serviceType = maintenance['serviceType'] as String? ?? 'unknown';
    final vehicleId = plateNumber ?? 'unknown_vehicle';
    final reminderType =
        maintenance['nextServiceMileage'] != null ? 'mileage' : 'date';
    final value =
        maintenance['nextServiceMileage'] ??
        maintenance['nextServiceDate'] ??
        'unknown';

    return '${widget.userId}_${vehicleId}_${serviceType}_${reminderType}_$value';
  }

  void _checkServiceReminders() {
    // Only check reminders once per session
    if (_remindersChecked) return;

    final nextService = getNextServiceInfo();
    if (nextService != null) {
      _checkSingleServiceReminder(nextService);
    }

    _remindersChecked = true;
  }

  void _checkSingleServiceReminder(Map<String, dynamic> maintenance) {
    final reminderId = _generateReminderId(maintenance);

    // Skip if this reminder has already been shown
    if (_shownReminderIds.contains(reminderId)) {
      return;
    }

    final serviceType = maintenance['serviceType'] as String? ?? 'Service';
    final nextServiceMileage = maintenance['nextServiceMileage'] as int?;
    final nextServiceDate = maintenance['nextServiceDate'] as String?;
    final vehicleInfo = '$make $model $plateNumber';

    bool shouldShowReminder = false;
    String reminderMessage = '';
    bool isUrgent = false;

    // Check mileage reminder (within 500km)
    if (nextServiceMileage != null && currentMileage != null) {
      final mileageDifference = nextServiceMileage - currentMileage!;
      if (mileageDifference <= 500 && mileageDifference > 0) {
        shouldShowReminder = true;
        reminderMessage = 'Your $serviceType is due in $mileageDifference km';
        isUrgent = mileageDifference <= 100;
      }
    }

    // Check date reminder (within 7 days)
    if (nextServiceDate != null && !shouldShowReminder) {
      try {
        final dueDate = DateTime.parse(nextServiceDate);
        final now = DateTime.now();
        final daysUntilDue = dueDate.difference(now).inDays;

        if (daysUntilDue <= 7 && daysUntilDue >= 0) {
          shouldShowReminder = true;
          reminderMessage = 'Your $serviceType is due in $daysUntilDue days';
          isUrgent = daysUntilDue <= 3;
        }

        if (daysUntilDue < 0 && !_shownReminderIds.contains(reminderId)) {
          shouldShowReminder = true;
          reminderMessage =
              'Your $serviceType is ${daysUntilDue.abs()} days overdue';
          isUrgent = true;
        }
      } catch (e) {
        debugPrint('Error checking service date: $e');
      }
    }

    if (shouldShowReminder) {
      _showServiceReminderSnackbar(
        isUrgent ? 'Service Reminder' : 'Service Due Soon',
        reminderMessage,
        reminderId: reminderId,
        isUrgent: isUrgent,
      );
    }
  }

  Future<void> _initializeChat() async {
    try {
      await _chatService.initialize('3mj9hufw92nk');
      final result = await _chatService.connectUser(
        userId: widget.userId,
        name: widget.userName ?? 'user',
        email: widget.userEmail,
      );

      if (result['success'] == true) {
        setState(() => _chatInitialized = true);
      } else {
        debugPrint('Chat initialization failed: ${result['error']}');
      }
    } catch (e) {
      debugPrint('Chat initialization error: $e');
    }
  }

  void _showServiceReminderSnackbar(
    String title,
    String message, {
    required String reminderId,
    bool isUrgent = false,
  }) {
    // Mark as shown immediately to prevent duplicates
    _shownReminderIds.add(reminderId);
    _saveShownReminders();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isUrgent ? Colors.white : Colors.white,
              ),
            ),
            Text(
              message,
              style: TextStyle(
                color: isUrgent ? Colors.white : Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ),
        backgroundColor: isUrgent
            ? Colors.orange.shade700  // Orange for warnings
            : AppColors.primaryColor,
        action: SnackBarAction(
          label: 'Book Now',
          textColor: Colors.white,
          backgroundColor: isUrgent ? Colors.orange.shade900 : Colors.deepOrange.shade700,
          onPressed: () {
            Navigator.pushNamed(
              context,
              'search-service-center',
              arguments: {
                'userId': widget.userId,
                'userName': widget.userName,
                'userEmail': widget.userEmail,
              },
            );
          },
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _clearShownReminders() {
    _shownReminderIds.clear();
    _saveShownReminders();
    _remindersChecked = false;
  }

  Future<void> _loadAll() async {
    final userId = widget.userId;
    if (userId.isEmpty) {
      setState(() => loading = false);
      return;
    }

    try {
      await _loadOwnerAndVehicle(userId);
      await _loadLocation();
      await Future.wait([
        _loadLatestAppointment(userId),
        _loadLatestTowingRequest(userId),
      ]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkServiceReminders();
      });
    } catch (e) {
      debugPrint('Homepage error: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadOwnerAndVehicle(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(uid)
              .get();

      if (!doc.exists) return;

      final data = doc.data()!;

      // Owner fields
      ownerName = data['name'] as String? ?? 'User';
      ownerEmail = data['email'] as String?;
      ownerPhone = data['phone'] as String?;

      // Load all vehicles
      if (data['vehicles'] != null) {
        final allVehiclesFromCarOwner = List<Map<String, dynamic>>.from(
          data['vehicles'] as List,
        );

        allVehicles =
            allVehiclesFromCarOwner.where((vehicle) {
              return vehicle['status']?.toString().toLowerCase() == 'approved';
            }).toList();

        // Find default vehicle or use first vehicle
        currentVehicleIndex = allVehicles.indexWhere(
          (vehicle) => vehicle['isDefault'] == true,
        );

        if (currentVehicleIndex == -1 && allVehicles.isNotEmpty) {
          currentVehicleIndex = 0;
        }

        if (allVehicles.isNotEmpty) {
          _updateCurrentVehicle(currentVehicleIndex);
        }
      }
    } catch (e) {
      debugPrint('Owner/Vehicle loading error: $e');
    }
  }

  void _updateCurrentVehicle(int index) {
    if (index >= 0 && index < allVehicles.length) {
      currentVehicle = allVehicles[index];
      currentVehicleIndex = index;

      // Update vehicle fields
      final vehicle = currentVehicle!;
      plateNumber = vehicle['plateNumber'] as String?;
      make = vehicle['make'] as String?;
      model = vehicle['model'] as String?;
      year = vehicle['year']?.toString();
      fuelType = vehicle['fuelType'] as String?;
      displacement = vehicle['displacement']?.toString();
      sizeClass = vehicle['sizeClass'] as String?;
      currentMileage = vehicle['lastServiceMileage'] as int?;

      // Load service maintenances
      serviceMaintenances = [];
      if (vehicle['serviceMaintenances'] != null) {
        serviceMaintenances = List<Map<String, dynamic>>.from(
          vehicle['serviceMaintenances'] as List,
        );
      }
    }
  }

  Future<void> _switchVehicle() async {
    if (allVehicles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Only one vehicle available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildVehicleSelectionSheet(),
    );
  }

  Widget _buildVehicleSelectionSheet() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.directions_car, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Select Vehicle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Vehicle List
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: allVehicles.length,
              itemBuilder: (context, index) {
                final vehicle = allVehicles[index];
                final isSelected = index == currentVehicleIndex;
                final isDefault = vehicle['isDefault'] == true;

                return _buildVehicleListItem(
                  vehicle: vehicle,
                  index: index,
                  isSelected: isSelected,
                  isDefault: isDefault,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleListItem({
    required Map<String, dynamic> vehicle,
    required int index,
    required bool isSelected,
    required bool isDefault,
  }) {
    final vehicleMake = vehicle['make'] as String? ?? 'Unknown';
    final vehicleModel = vehicle['model'] as String? ?? 'Unknown';
    final vehicleYear = vehicle['year']?.toString();
    final plateNum = vehicle['plateNumber'] as String? ?? 'No Plate';
    final mileage = vehicle['lastServiceMileage'] as int?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color:
            isSelected
                ? AppColors.primaryColor.withOpacity(0.1)
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _selectVehicle(index);
            Navigator.pop(context);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Vehicle Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      (vehicleMake != 'Unknown' &&
                              vehicleModel != 'Unknown' &&
                              vehicleYear != null)
                          ? Image.network(
                            'https://cdn.imagin.studio/getImage?customer=demo&make=$vehicleMake&modelFamily=$vehicleModel&modelYear=$vehicleYear&angle=01',
                            height: 60,
                            width: 80,
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Container(
                                  height: 60,
                                  width: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.directions_car,
                                    color: Colors.grey.shade400,
                                    size: 24,
                                  ),
                                ),
                          )
                          : Container(
                            height: 60,
                            width: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.directions_car,
                              color: Colors.grey.shade400,
                              size: 24,
                            ),
                          ),
                ),

                const SizedBox(width: 12),

                // Vehicle Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plateNum,
                        style: TextStyle(
                          color:
                              isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.secondaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$vehicleMake $vehicleModel${vehicleYear != null ? ' ($vehicleYear)' : ''}',
                        style: TextStyle(
                          color:
                              isSelected
                                  ? AppColors.primaryColor.withOpacity(0.8)
                                  : Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      if (mileage != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Mileage: ${mileage.toStringAsFixed(0)} km',
                          style: TextStyle(
                            color:
                                isSelected
                                    ? AppColors.primaryColor.withOpacity(0.6)
                                    : Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Selection and Default Indicators
                Column(
                  children: [
                    if (isSelected) ...[
                      Icon(
                        Icons.check_circle,
                        color: AppColors.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (isDefault) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DEFAULT',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectVehicle(int index) async {
    if (index == currentVehicleIndex) return;

    try {
      // Clear old reminders before switching
      _clearShownReminders();

      // Update local state first for immediate feedback
      _updateCurrentVehicle(index);

      await _updateDefaultVehicle(index);

      if (mounted) {
        setState(() {});
      }

      // Check reminders for new vehicle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkServiceReminders();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${allVehicles[index]['plateNumber']}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error switching vehicle: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to switch vehicle'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateDefaultVehicle(int newDefaultIndex) async {
    try {
      final userId = widget.userId;
      final updatedVehicles = List<Map<String, dynamic>>.from(allVehicles);

      // Update all vehicles' isDefault field
      for (int i = 0; i < updatedVehicles.length; i++) {
        updatedVehicles[i]['isDefault'] = (i == newDefaultIndex);
      }

      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(userId)
          .update({'vehicles': updatedVehicles});

      // Update local list
      allVehicles = updatedVehicles;
    } catch (e) {
      debugPrint('Error updating default vehicle: $e');
      rethrow;
    }
  }

  Future<void> _loadLatestTowingRequest(String uid) async {
    try {
      final towingQuerySnapshot =
          await FirebaseFirestore.instance
              .collection('towing_requests')
              .where('userId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (towingQuerySnapshot.docs.isNotEmpty) {
        final towingDoc = towingQuerySnapshot.docs.first;
        final towingData = towingDoc.data();

        setState(() {
          towingRequestId = towingDoc.id;
          towingStatus = towingData['status'];
          towingCreatedAt = towingData['createdAt'];
          towingEstimatedCost = towingData['estimatedCost']?.toDouble();
        });

        // Format date
        if (towingCreatedAt != null) {
          final date = towingCreatedAt!.toDate();
          towingDateStr =
              '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
        }

        // Get vehicle info
        final vehicleInfo = towingData['vehicleInfo'];
        if (vehicleInfo != null) {
          towingVehicleInfo =
              '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''} ${vehicleInfo['plateNumber'] ?? ''}'
                  .trim();
        }

        // Get service center name
        final serviceCenterId = towingData['serviceCenterId'];
        if (serviceCenterId != null) {
          final scQuerySnapshot =
              await FirebaseFirestore.instance
                  .collection('service_centers')
                  .doc(serviceCenterId)
                  .get();

          if (scQuerySnapshot.exists) {
            final scData = scQuerySnapshot.data()!;
            towingServiceCenterName =
                scData['name'] ??
                scData['serviceCenterInfo']?['name'] ??
                'Service Center';
          }
        }

        debugPrint('Towing request loaded: $towingStatus');
      } else {
        setState(() {
          towingStatus = null;
          towingRequestId = null;
        });
      }
    } catch (e) {
      debugPrint('Towing request loading error: $e');
      setState(() {
        towingStatus = null;
        towingRequestId = null;
      });
    }
  }

  Future<void> _loadLatestAppointment(String uid) async {
    try {
      final now = DateTime.now();

      final apptQuerySnapshot =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .where('userId', isEqualTo: uid)
              .where('scheduledDate', isGreaterThanOrEqualTo: now)
              .orderBy('scheduledDate', descending: false)
              .limit(1)
              .get();

      if (apptQuerySnapshot.docs.isNotEmpty) {
        final apptDoc = apptQuerySnapshot.docs.first;
        final apptData = apptDoc.data();

        setState(() {
          apptStatus = apptData['status'];
          apptServiceType = apptData['selectionType'] ?? 'General Service';
          apptRequestId = apptDoc.id;
        });

        // Get current mileage from booking
        final bookingMileage = apptData['currentMileage'] as int?;
        if (bookingMileage != null) {
          debugPrint('Booking recorded mileage: $bookingMileage');
        }

        // Get service maintenances from booking
        final bookingServiceMaintenances =
            apptData['serviceMaintenances'] as List?;
        if (bookingServiceMaintenances != null) {
          debugPrint(
            'Booking has ${bookingServiceMaintenances.length} service maintenances',
          );

          // Get upcoming service types for display
          final upcomingServices =
              bookingServiceMaintenances
                  .map((maintenance) {
                    return maintenance['serviceType']?.toString().replaceAll(
                          '_',
                          ' ',
                        ) ??
                        '';
                  })
                  .where((service) => service.isNotEmpty)
                  .toList();

          if (upcomingServices.isNotEmpty) {
            apptServiceType = upcomingServices.take(2).join(', ');
            if (upcomingServices.length > 2) {
              apptServiceType = ' +${upcomingServices.length - 2} more';
            }
          }
        }

        // Get services array for display
        final services = apptData['services'] as List?;
        if (services != null && services.isNotEmpty) {
          final serviceNames =
              services
                  .map((service) {
                    return service['serviceName']?.toString() ?? '';
                  })
                  .where((name) => name.isNotEmpty)
                  .toList();

          if (serviceNames.isNotEmpty) {
            apptServiceType = serviceNames.take(2).join(', ');
            if (serviceNames.length > 2) {
              apptServiceType = ' +${serviceNames.length - 2} more';
            }
          }
        }

        // Get preferred date and time
        final scheduledDate = apptData['scheduledDate'] as Timestamp?;
        final scheduledTime = apptData['scheduledTime'] as String?;

        if (scheduledDate != null) {
          final date = scheduledDate.toDate();
          final timeStr = scheduledTime ?? '00:00';
          apptDateStr = '${date.day}/${date.month}/${date.year} $timeStr';
        }

        // Get estimated duration
        final estimatedDuration = apptData['estimatedDuration'] as int?;
        if (estimatedDuration != null) {
          apptDuration = '${estimatedDuration} mins';
        }

        // Get urgency level
        final urgencyLevel = apptData['urgencyLevel'] as String?;
        if (urgencyLevel != null) {
          apptUrgency = urgencyLevel;
        }

        // Get vehicle info
        final vehicleInfo = apptData['vehicle'];
        if (vehicleInfo != null) {
          apptVehicleInfo =
              '${vehicleInfo['make'] ?? ''} ${vehicleInfo['model'] ?? ''} ${vehicleInfo['plateNumber'] ?? ''}'
                  .trim();
        }

        // Get service center name
        final serviceCenterId = apptData['serviceCenterId'];
        if (serviceCenterId != null) {
          final scQuerySnapshot =
              await FirebaseFirestore.instance
                  .collection('service_centers')
                  .doc(serviceCenterId)
                  .get();

          if (scQuerySnapshot.exists) {
            final scData = scQuerySnapshot.data()!;
            apptCenterName =
                scData['name'] ??
                scData['serviceCenterInfo']?['name'] ??
                'Service Center';
          }
        }

        // Get total amount if available
        final totalEstAmount = apptData['totalEstAmount'] as num?;
        final totalEstAmountRange = apptData['totalEstAmountRange'];

        if (totalEstAmountRange != null && totalEstAmountRange.isNotEmpty) {
          apptAmountRange = totalEstAmountRange;
        } else if (totalEstAmount != null && totalEstAmount > 0) {
          apptAmountFix = 'RM ${totalEstAmount.toStringAsFixed(2)}';
        }

        debugPrint('Appointment loaded: $apptStatus - $apptServiceType');
      }
    } catch (e) {
      debugPrint('Appointment loading error: $e');
    }
  }

  Future<void> _loadLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        currentLocation = 'Location services disabled';
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          currentLocation = 'Location permission denied';
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        currentLocation = 'Location permission permanently denied';
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];

        String city =
            place.locality?.isNotEmpty == true
                ? place.locality!
                : (place.subLocality?.isNotEmpty == true
                    ? place.subLocality!
                    : (place.subAdministrativeArea?.isNotEmpty == true
                        ? place.subAdministrativeArea!
                        : ''));

        String state = place.administrativeArea ?? '';
        currentLocation = city.isNotEmpty ? '$city, $state' : state;
      }
    } catch (e) {
      currentLocation = 'Unable to get location';
      debugPrint('Location error: $e');
    }
  }

  Map<String, dynamic>? getNextServiceInfo() {
    if (serviceMaintenances.isEmpty) return null;

    DateTime? closestDate;
    Map<String, dynamic>? closestService;

    for (var maintenance in serviceMaintenances) {
      final nextServiceDate = maintenance['nextServiceDate'] as String?;
      if (nextServiceDate != null) {
        try {
          final date = DateTime.parse(nextServiceDate);
          if (closestDate == null || date.isBefore(closestDate)) {
            closestDate = date;
            closestService = maintenance;
          }
        } catch (e) {
          debugPrint('Error parsing date: $e');
        }
      }
    }

    return closestService;
  }

  String getServiceTypeDisplay(String serviceType) {
    final displayNames = {
      'engine_oil': 'Engine Oil Change',
      'alignment': 'Wheel Alignment',
      'battery': 'Battery Replacement',
      'tire_rotation': 'Tire Rotation',
      'brake_fluid': 'Brake Fluid Change',
      'air_filter': 'Air Filter Replacement',
      'coolant': 'Coolant Replacement',
      'gear_oil': 'Gear Oil',
      'at_fluid': 'AT Fluid',
    };
    return displayNames[serviceType] ?? serviceType.replaceAll('_', ' ');
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _appointmentSubscription?.cancel();
    _towingSubscription?.cancel();
    _vehicleSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Loading your dashboard...',
                style: TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_isInitializingChat) ...[
                const SizedBox(height: 8),
                Text(
                  'Initializing chat...',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomNavBar(),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryColor,
          onRefresh: () async {
            _clearShownReminders();
            await _loadAll();
            if (!_chatInitialized && !_isInitializingChat) {
              await _initializeChat();
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildWelcomeHeader(),
                    const SizedBox(height: 24),
                    if (_chatError != null) _buildChatErrorCard(),
                    _buildVehicleCard(),
                    const SizedBox(height: 24),
                    _buildQuickActions(),
                    const SizedBox(height: 28),
                    _buildStatusCards(),
                    const SizedBox(height: 20),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.red.shade600,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat Service Issue',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Unable to connect to chat service. Pull down to refresh.',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _initializeChat,
            child: Text('Retry', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.cardColor,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            child: Image.asset(
              'assets/AutoMateLogoWithoutBackground.png',
              height: 60,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'AutoMate',
            style: TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        BlocBuilder<NotificationBloc, NotificationState>(
          builder: (context, state) {
            final unreadCount = state.notifications
                .where((notification) =>
            notification.userId == widget.userId &&
                !notification.isRead)
                .length;

            return NotificationBadge(
              count: unreadCount,
              icon: Container(
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.notifications_outlined,
                  color: AppColors.secondaryColor,
                  size: 20,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NotificationsPage(userId: widget.userId),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.logout, color: Colors.red, size: 20),
          ),
          onPressed: () async {
            await firebase_auth.FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/');
            }
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildWelcomeHeader() {
    final name = ownerName ?? 'User';
    final timeOfDay =
        DateTime.now().hour < 12
            ? 'morning'
            : DateTime.now().hour < 17
            ? 'afternoon'
            : 'evening';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good $timeOfDay,',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
        Text(
          name,
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.location_on, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              currentLocation ?? 'Location unavailable',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVehicleCard() {
    final nextService = getNextServiceInfo();
    final vehicleCount = allVehicles.length;
    final upcomingServices = getUpcomingServices();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryColor,
            AppColors.primaryColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main vehicle info row
          Row(
            children: [
              // Vehicle Image
              Container(
                width: 100,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      (make != null && model != null && year != null)
                          ? Image.network(
                            'https://cdn.imagin.studio/getImage?customer=demo&make=$make&modelFamily=$model&modelYear=$year&angle=01',
                            fit: BoxFit.cover,
                            errorBuilder:
                                (context, error, stackTrace) => Container(
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
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.directions_car,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 15),

              // Vehicle Details
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Your Vehicle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (vehicleCount > 1) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${currentVehicleIndex + 1}/$vehicleCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plateNumber ?? 'No Vehicle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (make != null && model != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$make $model${year != null ? ' ($year)' : ''}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (currentMileage != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.speed,
                                    size: 12,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Current Mileage',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${currentMileage!.toStringAsFixed(0)} km',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    // Show service maintenance count if available
                    if (upcomingServices.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.build_circle,
                            size: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${upcomingServices.length} upcoming service${upcomingServices.length > 1 ? 's' : ''}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Switch Vehicle Button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.swap_horiz,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                onPressed: _switchVehicle,
              ),
            ],
          ),

          if (upcomingServices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildUpcomingServicesCarousel(upcomingServices),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> getUpcomingServices() {
    if (serviceMaintenances.isEmpty) return [];

    final now = DateTime.now();
    final List<Map<String, dynamic>> upcomingServices = [];

    for (var maintenance in serviceMaintenances) {
      bool isDueSoon = false;

      // Check mileage-based services (within 500km)
      final nextServiceMileage = maintenance['nextServiceMileage'] as int?;
      if (nextServiceMileage != null && currentMileage != null) {
        final mileageDifference = nextServiceMileage - currentMileage!;
        if (mileageDifference <= 500 && mileageDifference >= 0) {
          isDueSoon = true;
        }
      }

      // Check date-based services (within 30 days)
      final nextServiceDate = maintenance['nextServiceDate'] as String?;
      if (nextServiceDate != null && !isDueSoon) {
        try {
          final dueDate = DateTime.parse(nextServiceDate);
          final daysUntilDue = dueDate.difference(now).inDays;
          if (daysUntilDue <= 30 && daysUntilDue >= 0) {
            isDueSoon = true;
          }
        } catch (e) {
          debugPrint('Error parsing service date: $e');
        }
      }

      // Check overdue services
      if (nextServiceDate != null && !isDueSoon) {
        try {
          final dueDate = DateTime.parse(nextServiceDate);
          if (dueDate.isBefore(now)) {
            isDueSoon = true;
          }
        } catch (e) {
          debugPrint('Error parsing overdue service date: $e');
        }
      }

      if (isDueSoon) {
        upcomingServices.add(maintenance);
      }
    }

    // Sort by urgency (overdue first, then by closest date/mileage)
    upcomingServices.sort((a, b) {
      final now = DateTime.now();

      // Check if overdue
      final aDate = _parseDate(a['nextServiceDate']);
      final bDate = _parseDate(b['nextServiceDate']);
      final aIsOverdue = aDate?.isBefore(now) ?? false;
      final bIsOverdue = bDate?.isBefore(now) ?? false;

      if (aIsOverdue && !bIsOverdue) return -1;
      if (!aIsOverdue && bIsOverdue) return 1;

      // Sort by closest date
      if (aDate != null && bDate != null) {
        return aDate.compareTo(bDate);
      }

      // Sort by closest mileage
      final aMileage = a['nextServiceMileage'] as int?;
      final bMileage = b['nextServiceMileage'] as int?;
      if (aMileage != null && bMileage != null && currentMileage != null) {
        final aDiff = aMileage - currentMileage!;
        final bDiff = bMileage - currentMileage!;
        return aDiff.compareTo(bDiff);
      }

      return 0;
    });

    return upcomingServices;
  }

  DateTime? _parseDate(String? dateString) {
    if (dateString == null) return null;
    try {
      return DateTime.parse(dateString);
    } catch (e) {
      return null;
    }
  }

  Widget _buildUpcomingServicesCarousel(
    List<Map<String, dynamic>> upcomingServices,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with indicator
        Row(
          children: [
            Icon(
              Icons.build_circle_outlined,
              color: Colors.white.withOpacity(0.8),
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'Upcoming Services',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (upcomingServices.length > 1)
              Text(
                'Swipe to view',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Carousel
        SizedBox(
          height: 150,
          child: PageView.builder(
            itemCount: upcomingServices.length,
            itemBuilder: (context, index) {
              final service = upcomingServices[index];
              return _buildServiceCard(service);
            },
          ),
        ),

        // Page indicator
        if (upcomingServices.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(upcomingServices.length, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.5),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final serviceType = service['serviceType'] as String? ?? 'unknown';
    final nextServiceMileage = service['nextServiceMileage'] as int?;
    final nextServiceDate = service['nextServiceDate'] as String?;
    final currentMileage = this.currentMileage;

    // Calculate urgency
    bool isOverdue = false;
    bool isDueSoon = false;
    String statusText = 'Reminder';
    Color statusColor = Colors.green;

    if (nextServiceDate != null) {
      try {
        final dueDate = DateTime.parse(nextServiceDate);
        final now = DateTime.now();
        final daysUntilDue = dueDate.difference(now).inDays;

        if (dueDate.isBefore(now)) {
          isOverdue = true;
          statusText = 'Overdue';
          statusColor = Colors.red;
        } else if (daysUntilDue <= 7) {
          isDueSoon = true;
          statusText = 'Due Soon';
          statusColor = Colors.orange;
        }
      } catch (e) {
        debugPrint('Error calculating service status: $e');
      }
    }

    // Check mileage urgency
    if (nextServiceMileage != null && currentMileage != null) {
      final mileageDifference = nextServiceMileage - currentMileage;
      if (mileageDifference <= 100 && mileageDifference >= 0 && !isOverdue) {
        isDueSoon = true;
        statusText = 'Due Soon';
        statusColor = Colors.orange;
      }
      if (mileageDifference < 0 && !isOverdue) {
        isOverdue = true;
        statusText = 'Overdue';
        statusColor = Colors.red;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(5, 0, 5, 0),
      decoration: BoxDecoration(
        color: AppColors.backgroundColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service Type and Status
          Row(
            children: [
              Expanded(
                child: Text(
                  getServiceTypeDisplay(serviceType),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Mileage Info
          if (nextServiceMileage != null && currentMileage != null) ...[
            Row(
              children: [
                Icon(Icons.speed, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Mileage Due at $nextServiceMileage km (${nextServiceMileage - currentMileage} km left)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],

          // Date Info
          if (nextServiceDate != null) ...[
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Service Due on: ${_formatServiceDate(nextServiceDate)}',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '(${_getDaysRemaining(nextServiceDate)})',
                  style: TextStyle(fontSize: 12, color: AppColors.errorColor),
                ),
              ],
            ),
          ],

          // Urgent warning for overdue services
          if (isOverdue) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning, size: 10),
                  const SizedBox(width: 4),
                  Text(
                    'Service required immediately',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getDaysRemaining(String dateString) {
    try {
      final dueDate = DateTime.parse(dateString);
      final now = DateTime.now();
      final daysUntilDue = dueDate.difference(now).inDays;

      if (daysUntilDue < 0) {
        return '${daysUntilDue.abs()} days overdue';
      } else if (daysUntilDue == 0) {
        return 'Due today';
      } else if (daysUntilDue == 1) {
        return 'Due tomorrow';
      } else {
        return '$daysUntilDue days remaining';
      }
    } catch (e) {
      return '';
    }
  }

  String _formatServiceDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildQuickActions() {
    final List<Map<String, dynamic>> actions = [
      {
        'label': 'Find Workshop',
        'icon': Icons.car_repair_outlined,
        'color': Colors.blue,
      },
      {
        'label': 'Search Service',
        'icon': Icons.build_outlined,
        'color': Colors.green,
      },
      {
        'label': 'Towing Service',
        'icon': Icons.emergency_outlined,
        'color': Colors.red,
      },
      {
        'label': 'Service History',
        'icon': Icons.history_outlined,
        'color': Colors.purple,
      },
      {
        'label': 'My Vehicle',
        'icon': Icons.directions_car_outlined,
        'color': Colors.orange,
      },
      {
        'label': 'Support Chat',
        'icon': Icons.support_agent_outlined,
        'color': Colors.teal,
      },
    ];

    final double screenWidth = MediaQuery.of(context).size.width;
    const double horizontalPadding = 10;
    const double spacing = 8;
    final double itemWidth =
        (screenWidth - horizontalPadding * 4 - spacing * 2) / 3;
    const double itemHeight = 110;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              actions.map((action) {
                return SizedBox(
                  width: itemWidth,
                  height: itemHeight,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 3,
                    shadowColor: AppColors.primaryColor.withOpacity(0.20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        if (action['label'] == 'Find Workshop') {
                          Navigator.pushNamed(
                            context,
                            'search-service-center',
                            arguments: {
                              'userId': widget.userId,
                              'userName': widget.userName,
                              'userEmail': widget.userEmail,
                            },
                          );
                        }
                        if (action['label'] == 'Search Service') {
                          Navigator.pushNamed(
                            context,
                            'search-services',
                            arguments: {'userId': widget.userId},
                          );
                        }
                        if (action['label'] == 'Towing Service') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => EmergencyTowingPage(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                  ),
                            ),
                          );
                        }
                        if (action['label'] == 'Service History') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => ServiceHistoryPage(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                    userEmail: widget.userEmail,
                                  ),
                            ),
                          );
                        }
                        if (action['label'] == 'My Vehicle') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => MyVehiclesPage(
                                    userId: widget.userId,
                                    userName: widget.userName,
                                  ),
                            ),
                          );
                        }
                        if (action['label'] == 'Support Chat') {
                          _navigateToSupportChat();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                action['icon'] as IconData,
                                color: (action['color'] as Color).withOpacity(
                                  0.65,
                                ),
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              action['label'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.secondaryColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  void _navigateToSupportChat() async {
    try {
      debugPrint('=== CHAT DEBUG INFO ===');
      debugPrint('User ID: ${widget.userId}');
      debugPrint('Chat client initialized: ${_chatService.client != null}');

      // Check if user is connected
      final currentUser = _chatService.client.state.currentUser;
      debugPrint('Current user: ${currentUser?.id}');
      debugPrint('User connected: ${currentUser != null}');

      if (currentUser == null) {
        debugPrint('User not connected to Stream Chat. Reconnecting...');
        final result = await _chatService.connectUser(
          userId: widget.userId,
          name: widget.userName ?? 'user',
          email: widget.userEmail,
        );

        if (result['success'] != true) {
          debugPrint('Failed to reconnect user: ${result['error']}');
          _showChatNotAvailable();
          return;
        }
        debugPrint('User reconnected successfully');
      }

      debugPrint('Creating support channel...');

      final channel = await _chatService.createAdminSupportChannel(
        customerId: widget.userId,
        customerName: widget.userName ?? 'user',
      );

      if (channel != null) {
        debugPrint('Support channel created successfully: ${channel.id}');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomerSupportChatPage(channel: channel),
          ),
        );
      } else {
        debugPrint('Failed to create support channel');
        _showChatNotAvailable();
      }
    } catch (e) {
      debugPrint('Error in support chat: $e');
      _showChatNotAvailable();
    }
  }

  void _showChatNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat is not available. Please try again later.'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: _initializeChat,
        ),
      ),
    );
  }

  Widget _buildStatusCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Activity',
          style: TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildStatusCard(
          title: 'Upcoming Towing Request',
          icon: Icons.local_shipping,
          color: AppColors.primaryColor,
          content: _buildTowingRequestContent(),
        ),
        const SizedBox(height: 16),
        _buildStatusCard(
          title: 'Upcoming Appointment',
          icon: Icons.event_available,
          color: Colors.orange,
          content: _buildAppointmentContent(),
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          title: 'Next Vehicle Service',
          icon: Icons.build_circle_outlined,
          color: Colors.blue,
          content: _buildNextServiceContent(),
        ),
      ],
    );
  }

  Widget _buildStatusCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget content,
  }) {
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
              Container(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.secondaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  Widget _buildTowingRequestContent() {
    if (towingStatus == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'No active towing requests',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _getTowingStatusBadge(towingStatus!),
        const SizedBox(height: 16),
        if (towingVehicleInfo != null && towingVehicleInfo!.isNotEmpty)
          _buildTowingInfoRow('Vehicle', towingVehicleInfo!),
        if (towingServiceCenterName != null)
          _buildTowingInfoRow('Service Center', towingServiceCenterName!),
        if (towingDateStr != null)
          _buildTowingInfoRow('Requested', towingDateStr!),
        if (towingEstimatedCost != null)
          _buildTowingInfoRow(
            'Estimated Cost',
            'RM ${towingEstimatedCost!.toStringAsFixed(2)}',
          ),

        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  // Navigate to tracking page
                  if (towingRequestId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => TowingRequestTrackingPage(
                              requestId: towingRequestId!,
                              userId: widget.userId,
                            ),
                      ),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  side: BorderSide(color: AppColors.primaryColor),
                ),
                child: const Text('Track Request'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTowingInfoRow(String label, String value) {
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

  Widget _getTowingStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;
    String statusText;

    switch (status) {
      case 'pending':
        backgroundColor = AppColors.warningColor.withOpacity(0.1);
        textColor = AppColors.warningColor;
        statusText = 'Pending';
        break;
      case 'accepted':
        backgroundColor = AppColors.primaryColor.withOpacity(0.1);
        textColor = AppColors.primaryColor;
        statusText = 'Accepted';
        break;
      case 'dispatched':
        backgroundColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue;
        statusText = 'Dispatched';
        break;
      case 'ongoing':
        backgroundColor = AppColors.primaryColor.withOpacity(0.1);
        textColor = AppColors.primaryColor;
        statusText = 'Ongoing';
        break;
      case 'completed':
        backgroundColor = AppColors.successColor.withOpacity(0.1);
        textColor = AppColors.successColor;
        statusText = 'Completed';
        break;
      case 'cancelled':
        backgroundColor = AppColors.errorColor.withOpacity(0.1);
        textColor = AppColors.errorColor;
        statusText = 'Cancelled';
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey;
        statusText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAppointmentContent() {
    if (apptStatus == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No upcoming appointments',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  'search-service-center',
                  arguments: {
                    'userId': widget.userId,
                    'userName': widget.userName,
                    'userEmail': widget.userEmail,
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Book Service Appointment'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _getStatusBadge(apptStatus!),
        const SizedBox(height: 16),
        if (apptServiceType != null) _buildInfoRow('Service', apptServiceType!),
        if (apptVehicleInfo != null && apptVehicleInfo!.isNotEmpty)
          _buildInfoRow('Vehicle', apptVehicleInfo!),
        if (apptDateStr != null) _buildInfoRow('Date & Time', apptDateStr!),
        if (apptDuration != null) _buildInfoRow('Duration', apptDuration!),
        if (apptCenterName != null)
          _buildInfoRow('Service Center', apptCenterName!),
        if (apptAmountRange != null && apptAmountRange!.isNotEmpty)
          _buildInfoRow('Estimated Amount', apptAmountRange!)
        else if (apptAmountFix != null && apptAmountFix!.isNotEmpty)
          _buildInfoRow('Estimated Amount', apptAmountFix!),

        const SizedBox(height: 12),

        // Status info with urgency
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getUrgencyColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: _getUrgencyColor()),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _getStatusMessage(),
                  style: TextStyle(
                    color: _getUrgencyColor(),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action buttons
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              if (apptRequestId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => ServiceAppointmentTrackingPage(
                          appointmentId: apptRequestId!,
                          userId: widget.userId,
                        ),
                  ),
                );
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryColor,
              side: BorderSide(color: AppColors.primaryColor),
            ),
            child: const Text('Track Appointment'),
          ),
        ),
      ],
    );
  }

  Color _getUrgencyColor() {
    switch (apptUrgency?.toLowerCase()) {
      case 'urgent':
        return AppColors.errorColor;
      case 'normal':
        return AppColors.successColor;
      default:
        return Colors.orange;
    }
  }

  String _getStatusMessage() {
    final status = apptStatus ?? '';
    final urgency = apptUrgency ?? '';

    String message = 'Appointment is ${status.replaceAll('_', ' ')}';

    if (urgency.isNotEmpty) {
      message += ' • ${urgency.toUpperCase()} priority';
    }

    return message;
  }

  Widget _getStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;
    String statusText;

    switch (status.toLowerCase()) {
      case 'pending':
        backgroundColor = AppColors.warningColor.withOpacity(0.1);
        textColor = AppColors.warningColor;
        statusText = 'Pending';
        break;
      case 'confirmed':
        backgroundColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue;
        statusText = 'Confirmed';
        break;
      case 'in_progress':
        backgroundColor = AppColors.primaryColor.withOpacity(0.1);
        textColor = AppColors.primaryColor;
        statusText = 'In Progress';
        break;
      case 'invoice_generated':
        backgroundColor = AppColors.primaryColor.withOpacity(0.1);
        textColor = AppColors.primaryColor;
        statusText = 'Invoice Generated';
        break;
      case 'completed':
        backgroundColor = AppColors.successColor.withOpacity(0.1);
        textColor = AppColors.successColor;
        statusText = 'Completed';
        break;
      case 'cancelled':
        backgroundColor = AppColors.errorColor.withOpacity(0.1);
        textColor = AppColors.errorColor;
        statusText = 'Cancelled';
        break;
      case 'declined':
        backgroundColor = AppColors.errorColor.withOpacity(0.1);
        textColor = AppColors.errorColor;
        statusText = 'Declined';
        break;
      default:
        backgroundColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey;
        statusText = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNextServiceContent() {
    final nextService = getNextServiceInfo();

    if (nextService == null) {
      return const Text(
        'No upcoming services scheduled',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    final daysUntilService = _getDaysUntilService(
      nextService['nextServiceDate'],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                daysUntilService <= 7
                    ? Colors.red.withOpacity(0.1)
                    : daysUntilService <= 30
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                daysUntilService <= 7
                    ? Icons.warning
                    : daysUntilService <= 30
                    ? Icons.info_outline
                    : Icons.check_circle,
                size: 14,
                color:
                    daysUntilService <= 7
                        ? Colors.red
                        : daysUntilService <= 30
                        ? Colors.orange
                        : Colors.green,
              ),
              const SizedBox(width: 4),
              Text(
                daysUntilService <= 0
                    ? 'Service overdue!'
                    : daysUntilService <= 7
                    ? 'Service due soon!'
                    : 'Reminder',
                style: TextStyle(
                  color:
                      daysUntilService <= 7
                          ? Colors.red
                          : daysUntilService <= 30
                          ? Colors.orange
                          : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          'Service Type',
          getServiceTypeDisplay(nextService['serviceType']),
        ),
        if (nextService['nextServiceMileage'] != null)
          _buildInfoRow(
            'Due Mileage',
            '${nextService['nextServiceMileage']} km',
          ),
        if (nextService['nextServiceDate'] != null)
          _buildInfoRow(
            'Due Date',
            _formatServiceDate(nextService['nextServiceDate']),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  int _getDaysUntilService(String? dateString) {
    if (dateString == null) return 999;
    try {
      final serviceDate = DateTime.parse(dateString);
      final now = DateTime.now();
      return serviceDate.difference(now).inDays;
    } catch (e) {
      return 999;
    }
  }

  Widget _buildInfoRow(String label, dynamic value) {
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

  BottomNavigationBar _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        if (index == 0) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => MyVehiclesPage(
                    userId: widget.userId,
                    userName: widget.userName,
                  ),
            ),
          );
        }
        if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MessageChatListPage(userId: widget.userId),
            ),
          );
        }
        if (index == 3) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CarOwnerProfilePage(userId: widget.userId),
            ),
          );
        }
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primaryColor,
      unselectedItemColor: Colors.grey.shade600,
      backgroundColor: AppColors.cardColor,
      elevation: 8,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.directions_car),
          label: 'Vehicle',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}

class ChannelPage extends StatelessWidget {
  final Channel channel;

  const ChannelPage({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StreamChannelHeader(),
      body: const Column(
        children: [
          Expanded(child: StreamMessageListView()),
          StreamMessageInput(),
        ],
      ),
    );
  }
}
