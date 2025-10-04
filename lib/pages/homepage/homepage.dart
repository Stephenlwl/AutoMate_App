import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:automate_application/pages/chat/message_chat_list_page.dart';
import 'package:automate_application/pages/chat/customer_support_chat_page.dart';
import 'package:automate_application/services/chat_service.dart';
import 'package:automate_application/pages/towing/request_towing_page.dart';
import 'package:automate_application/pages/service_history/service_hisotry_page.dart';
import 'package:automate_application/pages/my_vehicles/my_vehicles_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:stream_chat_flutter/stream_chat_flutter.dart' as stream_chat;
import '../../pages/notification/notification.dart';
import '../../widgets/notification_badge.dart';

class Homepage extends StatefulWidget {
  final String userId;
  final StreamChatClient chatClient;
  final String userName;
  final String userEmail;
  const Homepage({
    super.key,
    required this.userId,
    required this.chatClient,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
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
  String? apptStatus, apptDateStr, apptCenterName, apptServiceType;
  num? paymentAmount;
  String? paymentStatus, paymentDueStr;
  double? reviewRating;
  String? reviewComment, reviewCenterName;

  // Chat
  String? lastMessageText;
  String? lastMessageTimeStr;

  // Location
  String? currentLocation;

  bool loading = true;

  // App Colors
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initializeChat();
    _loadAll();
  }

  Future<void> _initializeChat() async {
    try {
      // Initialize with Stream API key
      await _chatService.initialize('3mj9hufw92nk');

      // Connect user
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

  Future<void> _loadAll() async {
    final userId = widget.userId;
    if (userId.isEmpty) {
      setState(() => loading = false);
      return;
    }

    try {
      await _loadOwnerAndVehicle(userId);
      await Future.wait([_loadLatestAppointment(userId), _loadLocation()]);
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
        allVehicles = List<Map<String, dynamic>>.from(
          data['vehicles'] as List,
        );

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
              color: primaryColor,
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
        color: isSelected ? primaryColor.withOpacity(0.1) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? primaryColor : Colors.transparent,
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
          onLongPress: () => _showVehicleOptions(vehicle, index),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Vehicle Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (vehicleMake != 'Unknown' && vehicleModel != 'Unknown' && vehicleYear != null)
                      ? Image.network(
                    'https://cdn.imagin.studio/getImage?customer=demo&make=$vehicleMake&modelFamily=$vehicleModel&modelYear=$vehicleYear&angle=01',
                    height: 60,
                    width: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
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
                          color: isSelected ? primaryColor : secondaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$vehicleMake $vehicleModel${vehicleYear != null ? ' ($vehicleYear)' : ''}',
                        style: TextStyle(
                          color: isSelected ? primaryColor.withOpacity(0.8) : Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      if (mileage != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Mileage: ${mileage.toStringAsFixed(0)} km',
                          style: TextStyle(
                            color: isSelected ? primaryColor.withOpacity(0.6) : Colors.grey.shade500,
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
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (isDefault) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
      // Update local state first for immediate feedback
      _updateCurrentVehicle(index);

      // Update Firestore to set this vehicle as default
      await _updateDefaultVehicle(index);

      if (mounted) {
        setState(() {});
      }

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

      // Update in Firestore
      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(userId)
          .update({
        'vehicles': updatedVehicles,
      });

      // Update local list
      allVehicles = updatedVehicles;
    } catch (e) {
      debugPrint('Error updating default vehicle: $e');
      rethrow;
    }
  }

  void _showVehicleOptions(Map<String, dynamic> vehicle, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text('Set as Default'),
              onTap: () {
                Navigator.pop(context);
                _selectVehicle(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.blue),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                _viewVehicleDetails(vehicle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.green),
              title: const Text('Service History'),
              onTap: () {
                Navigator.pop(context);
                _viewServiceHistory(vehicle);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _viewVehicleDetails(Map<String, dynamic> vehicle) {
    // Navigate to vehicle details page
    // You can implement this based on your app structure
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing details for ${vehicle['plateNumber']}'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _viewServiceHistory(Map<String, dynamic> vehicle) {
    // Navigate to service history for this specific vehicle
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServiceHistoryPage(
          userId: widget.userId,
          userName: widget.userName,
          userEmail: widget.userEmail,
        ),
      ),
    );
  }

  Future<void> _loadLatestAppointment(String uid) async {
    try {
      final apptQuerySnapshot = await FirebaseFirestore.instance
          .collection('service_bookings')
          .where('userId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (apptQuerySnapshot.docs.isNotEmpty) {
        final apptData = apptQuerySnapshot.docs.first.data();
        apptStatus = apptData['status'];
        apptServiceType = apptData['selectionType'] ?? 'General Service';

        // Get current mileage from booking
        final bookingMileage = apptData['currentMileage'] as int?;
        if (bookingMileage != null) {
          debugPrint('Booking recorded mileage: $bookingMileage');
        }

        // Get service maintenances from booking
        final bookingServiceMaintenances = apptData['serviceMaintenances'] as List?;
        if (bookingServiceMaintenances != null) {
          debugPrint('Booking has ${bookingServiceMaintenances.length} service maintenances');
        }

        // Get preferred date
        final preferredDate = apptData['scheduledDate'] as Timestamp?;
        if (preferredDate != null) {
          final date = preferredDate.toDate();
          apptDateStr = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
        }

        // Get service center name
        final serviceCenterId = apptData['serviceCenterId'];
        if (serviceCenterId != null) {
          final scQuerySnapshot = await FirebaseFirestore.instance
              .collection('service_centers')
              .doc(serviceCenterId)
              .get();

          if (scQuerySnapshot.exists) {
            final scData = scQuerySnapshot.data()!;
            apptCenterName = scData['name'] ??
                scData['serviceCenterInfo']?['name'] ??
                'Service Center';
          }
        }
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
    };
    return displayNames[serviceType] ?? serviceType.replaceAll('_', ' ');
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: primaryColor),
              const SizedBox(height: 16),
              Text(
                'Loading your dashboard...',
                style: TextStyle(
                  color: secondaryColor,
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

    Widget homepageContent = Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomNavBar(),
      body: RefreshIndicator(
        color: primaryColor,
        onRefresh: () async {
          await _loadAll();
          if (!_chatInitialized && !_isInitializingChat) {
            await _initializeChat();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWelcomeHeader(),
              const SizedBox(height: 24),
              if (_chatError != null) _buildChatErrorCard(),
              _buildVehicleCard(),
              const SizedBox(height: 24),
              _buildQuickActions(),
              const SizedBox(height: 28),
              _buildStatusCards(),
            ],
          ),
        ),
      ),
    );
    return homepageContent;
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
      backgroundColor: cardColor,
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
              color: secondaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        NotificationBadge(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.notifications_outlined,
              color: secondaryColor,
              size: 20,
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsPage()),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
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
            color: secondaryColor,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: (make != null && model != null && year != null)
                    ? Image.network(
                  'https://cdn.imagin.studio/getImage?customer=demo&make=$make&modelFamily=$model&modelYear=$year&angle=01',
                  height: 120,
                  width: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 120,
                    width: 100,
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
                  height: 120,
                  width: 100,
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
              const SizedBox(width: 15),
              Expanded(
                child: Column(
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                          Icon(Icons.speed, size: 12, color: Colors.white.withOpacity(0.8)),
                          const SizedBox(width: 4),
                          Text(
                            'Current Mileage: ${currentMileage!.toStringAsFixed(0)} km',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Show service maintenance count if available
                    if (serviceMaintenances.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.build_circle, size: 12, color: Colors.white.withOpacity(0.8)),
                          const SizedBox(width: 4),
                          Text(
                            '${serviceMaintenances.length} service schedules',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.swap_horiz,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: _switchVehicle,
              ),
            ],
          ),
          if (nextService != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    color: Colors.white.withOpacity(0.8),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next Service: ${getServiceTypeDisplay(nextService['serviceType'])}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (nextService['nextServiceMileage'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'At ${nextService['nextServiceMileage']} km',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (nextService['nextServiceDate'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'By ${_formatServiceDate(nextService['nextServiceDate'])}',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.notifications_active,
                    color: Colors.white.withOpacity(0.7),
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
            color: secondaryColor,
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
                    shadowColor: primaryColor.withOpacity(0.20),
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
                                  (context) =>
                                      MyVehiclesPage(userId: widget.userId),
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
                                color: secondaryColor,
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
            color: secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: secondaryColor,
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

  Widget _buildAppointmentContent() {
    if (apptStatus == null) {
      return const Text(
        'No upcoming appointments',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Status', _getStatusBadge(apptStatus!)),
        if (apptServiceType != null) _buildInfoRow('Service', apptServiceType!),
        if (apptDateStr != null) _buildInfoRow('Date & Time', apptDateStr!),
        if (apptCenterName != null) _buildInfoRow('Workshop', apptCenterName!),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text(
                'Appointment is ${apptStatus!.replaceAll('_', ' ')}',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
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
                    : 'Service scheduled',
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

  Widget _getStatusBadge(String status) {
    final statusColors = {
      'pending': Colors.orange,
      'confirmed': Colors.blue,
      'in_progress': Colors.purple,
      'ready_to_collect': Colors.green,
      'completed': Colors.green,
      'cancelled': Colors.red,
    };

    final color = statusColors[status] ?? Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child:
                value is Widget
                    ? value
                    : Text(
                      value.toString(),
                      style: const TextStyle(
                        fontSize: 13,
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
        if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MessageChatListPage(userId: widget.userId),
            ),
          );
        } else {
          setState(() => _selectedIndex = index);
        }
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: primaryColor,
      unselectedItemColor: Colors.grey.shade600,
      backgroundColor: cardColor,
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
