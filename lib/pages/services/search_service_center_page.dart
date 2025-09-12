import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'book_services_page.dart';
import 'package:automate_application/pages/chat/chat_page.dart';
import 'package:automate_application/services/chat_service.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color primaryLight = Color(0xFFF3A169);
  static const Color primaryDark = Color(0xFFE55D00);
  static const Color secondaryColor = Color(0xFF1E293B);
  static const Color backgroundColor = Color(0xFFFAFAFA);
  static const Color cardColor = Colors.white;
  static const Color surfaceColor = Color(0xFFF8F9FA);
  static const Color accentColor = Color(0xFF06B6D4);
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color borderColor = Color(0xFFE5E7EB);
}

class SearchServiceCenterPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;

  const SearchServiceCenterPage({super.key, required this.userId, required this.userName, required this.userEmail});

  @override
  State<SearchServiceCenterPage> createState() =>
      _SearchServiceCenterPageState();
}

class _SearchServiceCenterPageState extends State<SearchServiceCenterPage> {
  List<ServiceCenter> serviceCenters = [];
  List<ServiceCenter> filteredCenters = [];
  List<Map<String, dynamic>> serviceCategories = [];
  Position? currentPosition;
  String? currentLocation;
  bool loading = true;
  bool categoriesLoading = true;
  String searchQuery = '';
  String selectedFilter = 'All';
  String carOwnerVehicleMake = '';
  String carOwnerVehicleModel = '';
  String carOwnerVehicleYear = '';
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await Future.wait([
      _getUserVehicle(),
      _getCurrentLocation(),
      _loadServiceCategories(),
    ]);
    await _loadServiceCenters();
    _filterServiceCenters();
    setState(() => loading = false);
  }

  Future<void> _loadServiceCategories() async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('services_categories')
              .where('active', isEqualTo: true)
              .get();

      serviceCategories =
          querySnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'name': data['name'] ?? '',
              'description': data['description'] ?? '',
            };
          }).toList();

      setState(() => categoriesLoading = false);
    } catch (e) {
      debugPrint('Error loading service categories: $e');
      setState(() => categoriesLoading = false);
    }
  }

  Future<void> _getUserVehicle() async {
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

        if (vehicles.isNotEmpty) {
          final firstVehicle = vehicles.first;
          setState(() {
            carOwnerVehicleMake =
                firstVehicle['brand'] ?? firstVehicle['make'] ?? '';
            carOwnerVehicleModel = firstVehicle['model'] ?? '';
            carOwnerVehicleYear = firstVehicle['year']?.toString() ?? '';
          });
        }
      }
    } catch (err) {
      debugPrint('Error fetching user vehicle: $err');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        currentPosition = await Geolocator.getCurrentPosition();

        List<Placemark> placemarks = await placemarkFromCoordinates(
          currentPosition!.latitude,
          currentPosition!.longitude,
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
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _loadServiceCenters() async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('service_centers')
              .where('verification.status', isEqualTo: 'approved')
              .get();

      serviceCenters = [];

      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final center = ServiceCenter.fromFirestore(doc.id, data);

          final offers = await getOffersWithServiceNames(center.id);
          center.services =
              offers
                  .map((o) => o.serviceName ?? o.serviceDescription)
                  .whereType<String>()
                  .toList();

          serviceCenters.add(center);
        } catch (e, stackTrace) {
          debugPrint("Error processing service center ${doc.id}: $e");
          continue;
        }
      }

      if (currentPosition != null) {
        for (var center in serviceCenters) {
          final lat = center.latitude ?? 0.0;
          final lng = center.longitude ?? 0.0;

          center.distance =
              Geolocator.distanceBetween(
                currentPosition!.latitude,
                currentPosition!.longitude,
                lat,
                lng,
              ) /
              1000;
        }
        serviceCenters.sort(
          (a, b) => (a.distance ?? double.infinity).compareTo(
            b.distance ?? double.infinity,
          ),
        );
      }
    } catch (e) {
      debugPrint('Service centers loading error: $e');
    }
  }

  void _filterServiceCenters() {
    filteredCenters =
        serviceCenters.where((center) {
          final matchesSearch =
              center.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              center.city.toLowerCase().contains(searchQuery.toLowerCase()) ||
              center.state.toLowerCase().contains(searchQuery.toLowerCase());

          final matchesFilter =
              selectedFilter == 'All' ||
              center.services.any(
                (service) => service.toLowerCase().contains(
                  selectedFilter.toLowerCase(),
                ),
              );
          return matchesSearch && matchesFilter;
        }).toList();
  }

  Future<List<ServiceCenterServiceOffer>> getOffersWithServiceNames(
    String centerId,
  ) async {
    final query =
        await FirebaseFirestore.instance
            .collection('service_center_services_offer')
            .where('serviceCenterId', isEqualTo: centerId)
            .where('active', isEqualTo: true)
            .get();

    final offers =
        query.docs
            .map(
              (doc) =>
                  ServiceCenterServiceOffer.fromFirestore(doc.id, doc.data()),
            )
            .toList();

    final serviceIds = offers.map((o) => o.serviceId).toSet().toList();
    if (serviceIds.isEmpty) return offers;

    final serviceQuery =
        await FirebaseFirestore.instance
            .collection('services')
            .where(FieldPath.documentId, whereIn: serviceIds)
            .get();

    final serviceMap = {
      for (var doc in serviceQuery.docs) doc.id: doc['name'] ?? '',
    };

    for (var offer in offers) {
      offer.serviceName = serviceMap[offer.serviceId];
    }

    return offers;
  }

  Widget _buildServiceImage(String imageStr) {
    try {
      if (imageStr.startsWith('data:image')) {
        final base64Str = imageStr.split(',').last;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint("Base64 image error: $error");
            return _buildDefaultHeader();
          },
        );
      } else {
        return Image.network(
          imageStr,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor.withOpacity(0.8),
                    AppColors.primaryLight.withOpacity(0.8),
                  ],
                ),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value:
                      loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                  color: Colors.white,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Image loading error: $error');
            return _buildDefaultHeader();
          },
        );
      }
    } catch (e) {
      debugPrint("Image build error: $e");
      return _buildDefaultHeader();
    }
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.amber, size: 16);
        } else if (index < rating) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 16);
        } else {
          return const Icon(Icons.star_border, color: Colors.grey, size: 16);
        }
      }),
    );
  }

  Map<String, dynamic> _getOperatingStatus(
    List<Map<String, dynamic>> operatingHours,
  ) {
    if (operatingHours.isEmpty) {
      return {'status': 'Unknown', 'isOpen': false};
    }

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
    final currentTime = TimeOfDay.now();

    final todayHours = operatingHours.firstWhere(
      (hours) => hours['day'] == currentDay,
      orElse: () => {},
    );

    if (todayHours.isEmpty || todayHours['isClosed'] == true) {
      return {'status': 'Closed', 'isOpen': false};
    }

    try {
      final openTime = TimeOfDay(
        hour: int.parse(todayHours['open'].split(':')[0]),
        minute: int.parse(todayHours['open'].split(':')[1]),
      );
      final closeTime = TimeOfDay(
        hour: int.parse(todayHours['close'].split(':')[0]),
        minute: int.parse(todayHours['close'].split(':')[1]),
      );

      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      final openMinutes = openTime.hour * 60 + openTime.minute;
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;

      if (currentMinutes >= openMinutes && currentMinutes <= closeMinutes) {
        return {'status': 'Open', 'isOpen': true};
      } else if (currentMinutes < openMinutes) {
        return {'status': 'Opens at ${todayHours['open']}', 'isOpen': false};
      } else {
        return {'status': 'Closed', 'isOpen': false};
      }
    } catch (e) {
      return {'status': 'Unknown', 'isOpen': false};
    }
  }

  Color _getStatusColor(bool isOpen) {
    return isOpen ? AppColors.successColor : AppColors.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          title: const Text(
            'Find Service Centers',
            style:
            TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: AppColors.secondaryColor,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 180,
                floating: false,
                pinned: true,
                elevation: 0,
                backgroundColor: AppColors.secondaryColor,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    'Find Service Centers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black.withOpacity(0.4),
                        ),
                      ],
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.secondaryColor,
                          AppColors.backgroundColor,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Search Bar
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: searchController,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Search by name or location...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: Colors.grey.shade600,
                                    size: 24,
                                  ),
                                  suffixIcon:
                                      searchController.text.isNotEmpty
                                          ? IconButton(
                                            icon: Icon(
                                              Icons.clear_rounded,
                                              color: Colors.grey.shade600,
                                            ),
                                            onPressed: () {
                                              searchController.clear();
                                              setState(() {
                                                searchQuery = '';
                                                _filterServiceCenters();
                                              });
                                            },
                                          )
                                          : null,
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: AppColors.primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    searchQuery = value;
                                    _filterServiceCenters();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
        body: Column(
          children: [
            // Filter Chips
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildFilterChip('All'),
                    if (!categoriesLoading)
                      ...serviceCategories.map(
                        (category) => _buildFilterChip(category['name']),
                      ),
                  ],
                ),
              ),
            ),

            // Location Info
            if (currentLocation != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: AppColors.accentColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Location',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            currentLocation!,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${filteredCenters.length} found',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Service Centers List
            Expanded(
              child:
                  filteredCenters.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.textMuted.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No service centers found',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try adjusting your search or filters',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filteredCenters.length,
                        itemBuilder:
                            (context, index) =>
                                _buildServiceCenterCard(filteredCenters[index]),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String filter) {
    final isSelected = selectedFilter == filter;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: FilterChip(
        label: Text(
          filter,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            selectedFilter = filter;
            _filterServiceCenters();
          });
        },
        backgroundColor: Colors.white,
        selectedColor: AppColors.primaryColor,
        checkmarkColor: Colors.white,
        side: BorderSide(
          color: isSelected ? AppColors.primaryColor : AppColors.borderColor,
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      ),
    );
  }

  Widget _buildServiceCenterCard(ServiceCenter center) {
    final operatingInfo = _getOperatingStatus(center.operatingHours);
    final statusColor = _getStatusColor(operatingInfo['isOpen']);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Card(
        elevation: 3,
        shadowColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showServiceCenterDetails(center),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Image
              Stack(
                children: [
                  Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryColor.withOpacity(0.8),
                          AppColors.primaryLight.withOpacity(0.8),
                        ],
                      ),
                    ),
                    child:
                        center.serviceCenterPhoto.isNotEmpty
                            ? ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                              child: _buildServiceImage(
                                center.serviceCenterPhoto,
                              ),
                            )
                            : _buildDefaultHeader(),
                  ),

                  // Status and Distance Badges
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Distance Badge
                        if (center.distance != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.near_me_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${center.distance!.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Operating Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                operatingInfo['status'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
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

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Rating
                    Text(
                      center.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Rating
                    Row(
                      children: [
                        _buildStarRating(center.rating),
                        const SizedBox(width: 8),
                        Text(
                          '${center.rating.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' (${center.reviewCount} reviews)',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Address
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.textMuted.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "${center.addressLine1}, ${center.city}, ${center.state} ${center.postalCode}",
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Services
                    if (center.services.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            center.services
                                .take(3)
                                .map(
                                  (service) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryColor.withOpacity(
                                        0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.primaryColor
                                            .withOpacity(0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      service,
                                      style: TextStyle(
                                        color: AppColors.primaryColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),

                    if (center.services.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '+${center.services.length - 3} more services',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.call_rounded, size: 16),
                            label: const Text(
                              'Call',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryColor,
                              side: BorderSide(
                                color: AppColors.primaryColor,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed:
                                () => _callServiceCenter(
                                  center.serviceCenterPhoneNo,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Book Service',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: AppColors.primaryColor.withOpacity(
                                0.3,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _bookService(center),
                          ),
                        ),
                      ],
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

  Widget _buildDefaultHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryColor.withOpacity(0.8),
            AppColors.primaryLight.withOpacity(0.8),
          ],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.home_repair_service_rounded,
          color: Colors.white,
          size: 48,
        ),
      ),
    );
  }

  void _showServiceCenterDetails(ServiceCenter center) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (context, scrollController) {
              return ServiceCenterDetailsSheet(
                userId: widget.userId,
                userName: widget.userName,
                userEmail: widget.userEmail,
                center: center,
                scrollController: scrollController,
                onBook: () => _bookService(center),
                onCall: () => _callServiceCenter(center.serviceCenterPhoneNo),
                onDirections: () => _getDirections(center),
              );
            },
          ),
    );
  }

  void _callServiceCenter(String phoneNumber) async {
    final uri = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to make phone call'),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _getDirections(ServiceCenter center) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${center.latitude},${center.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to open directions'),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _bookService(ServiceCenter center) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) =>
                BookServicePage(userId: widget.userId, serviceCenter: center),
      ),
    );
  }
}

// Service Center Details Bottom Sheet
class ServiceCenterDetailsSheet extends StatefulWidget {
  final String userId;
  final String? userName;
  final String? userEmail;
  final ServiceCenter center;
  final ScrollController scrollController;
  final VoidCallback onBook;
  final VoidCallback onCall;
  final VoidCallback onDirections;

  const ServiceCenterDetailsSheet({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.center,
    required this.scrollController,
    required this.onBook,
    required this.onCall,
    required this.onDirections,
  });

  @override
  State<ServiceCenterDetailsSheet> createState() =>
      _ServiceCenterDetailsSheetState();
}

class _ServiceCenterDetailsSheetState extends State<ServiceCenterDetailsSheet> {
  final ChatService _chatService = ChatService();
  PageController? _pageController;
  int _currentImageIndex = 0;
  bool _chatInitialized = false;
  bool _isInitializingChat = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Initialize chat when the sheet opens
    _initializeChat();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (_isInitializingChat) return;

    setState(() => _isInitializingChat = true);

    try {
      await _chatService.initialize('3mj9hufw92nk');

      // Connect user
      final result = await _chatService.connectUser(
        userId: widget.userId,
        name: widget.userName ?? 'User',
        email: widget.userEmail,
      );

      if (result['success'] == true) {
        setState(() => _chatInitialized = true);
      } else {
        debugPrint('Chat initialization failed: ${result['error']}');
      }
    } catch (e) {
      debugPrint('Chat initialization error: $e');
    } finally {
      setState(() => _isInitializingChat = false);
    }
  }

  void _navigateToServiceCenterChat() async {
    try {
      final channel = await _chatService.createServiceCenterChannel(
          customerId: widget.userId,
          customerName: widget.userName ?? 'user',
          centerId: widget.center.id,
          centerName: widget.center.name
      );

      if (channel != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatPage(userId: widget.userId, channel: channel),
          ),
        );
      } else {
        _showChatNotAvailable();
      }
    } catch (e) {
      debugPrint('Error navigating to support chat: $e');
      _showChatNotAvailable();
    }
  }

  void _showChatNotAvailable() {
    if (!mounted) return;

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

  // Create list with serviceCenterPhoto first, then all other images
  List<String> get _allImages {
    final List<String> allImages = [];

    // Add serviceCenterPhoto first if it exists and is not empty
    if (widget.center.serviceCenterPhoto.isNotEmpty) {
      allImages.add(widget.center.serviceCenterPhoto);
    }

    // Add all other images, excluding serviceCenterPhoto if it's already added
    for (String image in widget.center.images) {
      if (image != widget.center.serviceCenterPhoto && image.isNotEmpty) {
        allImages.add(image);
      }
    }

    return allImages;
  }

  Widget buildServiceImage(String imageData) {
    if (imageData.startsWith('data:image')) {
      // Strip header and decode Base64
      final base64Str = imageData.split(',').last;
      final bytes = base64Decode(base64Str);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryColor.withOpacity(0.8),
                  AppColors.primaryLight.withOpacity(0.8),
                ],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.broken_image_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          );
        },
      );
    } else if (imageData.startsWith('http')) {
      return Image.network(
        imageData,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryColor.withOpacity(0.8),
                  AppColors.primaryLight.withOpacity(0.8),
                ],
              ),
            ),
            child: Center(
              child: CircularProgressIndicator(
                value:
                loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                    : null,
                color: Colors.white,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryColor.withOpacity(0.8),
                  AppColors.primaryLight.withOpacity(0.8),
                ],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.broken_image_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          );
        },
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryColor.withOpacity(0.8),
              AppColors.primaryLight.withOpacity(0.8),
            ],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.home_repair_service_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
      );
    }
  }

  Widget _buildStarRating(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, color: Colors.amber, size: 18);
        } else if (index < rating) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 18);
        } else {
          return const Icon(Icons.star_border, color: Colors.grey, size: 18);
        }
      }),
    );
  }

  Map<String, dynamic> _getOperatingStatus(
      List<Map<String, dynamic>> operatingHours,
      ) {
    if (operatingHours.isEmpty) {
      return {'status': 'Unknown', 'isOpen': false};
    }

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
    final currentTime = TimeOfDay.now();

    final todayHours = operatingHours.firstWhere(
          (hours) => hours['day'] == currentDay,
      orElse: () => {},
    );

    if (todayHours.isEmpty || todayHours['isClosed'] == true) {
      return {'status': 'Closed', 'isOpen': false};
    }

    try {
      final openTime = TimeOfDay(
        hour: int.parse(todayHours['open'].split(':')[0]),
        minute: int.parse(todayHours['open'].split(':')[1]),
      );
      final closeTime = TimeOfDay(
        hour: int.parse(todayHours['close'].split(':')[0]),
        minute: int.parse(todayHours['close'].split(':')[1]),
      );

      final currentMinutes = currentTime.hour * 60 + currentTime.minute;
      final openMinutes = openTime.hour * 60 + openTime.minute;
      final closeMinutes = closeTime.hour * 60 + closeTime.minute;

      if (currentMinutes >= openMinutes && currentMinutes <= closeMinutes) {
        return {'status': 'Open Now', 'isOpen': true};
      } else if (currentMinutes < openMinutes) {
        return {'status': 'Opens at ${todayHours['open']}', 'isOpen': false};
      } else {
        return {'status': 'Closed', 'isOpen': false};
      }
    } catch (e) {
      return {'status': 'Unknown', 'isOpen': false};
    }
  }

  @override
  Widget build(BuildContext context) {
    final operatingInfo = _getOperatingStatus(widget.center.operatingHours);
    final allImages = _allImages;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                // Image Gallery
                if (allImages.isNotEmpty)
                  Column(
                    children: [
                      Container(
                        height: 220,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            children: [
                              PageView.builder(
                                controller: _pageController,
                                onPageChanged: (index) {
                                  setState(() {
                                    _currentImageIndex = index;
                                  });
                                },
                                itemCount: allImages.length,
                                itemBuilder: (context, index) {
                                  return buildServiceImage(allImages[index]);
                                },
                              ),

                              // Image indicators
                              if (allImages.length > 1)
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children:
                                    allImages.asMap().entries.map((entry) {
                                      return Container(
                                        width:
                                        _currentImageIndex == entry.key
                                            ? 24
                                            : 8,
                                        height: 8,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                          BorderRadius.circular(4),
                                          color:
                                          _currentImageIndex ==
                                              entry.key
                                              ? Colors.white
                                              : Colors.white
                                              .withOpacity(0.5),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),

                              // Image counter
                              if (allImages.length > 1)
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_currentImageIndex + 1}/${allImages.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                // Title, Rating and Status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.center.name,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _buildStarRating(widget.center.rating),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.center.rating.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' (${widget.center.reviewCount} reviews)',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                        operatingInfo['isOpen']
                            ? AppColors.successColor
                            : AppColors.errorColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            operatingInfo['status'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Contact Information
                _buildInfoSection(
                  title: 'Contact Information',
                  icon: Icons.contact_phone_rounded,
                  children: [
                    _buildInfoRow(
                      Icons.location_on_rounded,
                      'Address',
                      "${widget.center.addressLine1}, ${widget.center.city}, ${widget.center.state} ${widget.center.postalCode}",
                    ),
                    _buildInfoRow(
                      Icons.phone_rounded,
                      'Contact Number',
                      widget.center.serviceCenterPhoneNo,
                    ),
                    _buildInfoRow(
                      Icons.email_rounded,
                      'Email',
                      widget.center.email,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Operating Hours
                _buildInfoSection(
                  title: 'Operating Hours',
                  icon: Icons.schedule_rounded,
                  children:
                  widget.center.operatingHours.map((entry) {
                    final isClosed = entry['isClosed'] == true;
                    final day = entry['day'] ?? '';
                    final hours =
                    isClosed
                        ? 'Closed'
                        : '${entry['open'] ?? ''} - ${entry['close'] ?? ''}';

                    return _buildOperatingHourRow(day, hours, isClosed);
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // Description
                if (widget.center.description.isNotEmpty)
                  _buildInfoSection(
                    title: 'About Us',
                    icon: Icons.info_outline_rounded,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.borderColor),
                        ),
                        child: Text(
                          widget.center.description,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Services
                if (widget.center.services.isNotEmpty)
                  _buildInfoSection(
                    title: 'Services Offered',
                    icon: Icons.build_rounded,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                        widget.center.services
                            .map(
                              (service) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryColor.withOpacity(
                                0.1,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primaryColor
                                    .withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              service,
                              style: TextStyle(
                                color: AppColors.primaryColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                            .toList(),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Distance
                if (widget.center.distance != null)
                  _buildInfoSection(
                    title: 'Distance',
                    icon: Icons.directions_rounded,
                    children: [
                      _buildInfoRow(
                        Icons.near_me_rounded,
                        'Distance from you',
                        '${widget.center.distance!.toStringAsFixed(1)} km away',
                      ),
                    ],
                  ),

                const SizedBox(height: 40),
              ],
            ),
          ),

          // Action Buttons - Updated to include Chat button
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              border: Border(top: BorderSide(color: AppColors.borderColor)),
            ),
            child: Column(
              children: [
                // Top row with Call, Chat, and Directions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text(
                          'Call',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryColor,
                          side: BorderSide(
                            color: AppColors.primaryColor,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: widget.onCall,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Chat Button
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _isInitializingChat
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : const Icon(Icons.chat_rounded, size: 18),
                        label: Text(
                          _isInitializingChat ? 'Loading...' : 'Chat',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _chatInitialized
                              ? Colors.green
                              : (_isInitializingChat ? Colors.grey : AppColors.accentColor),
                          side: BorderSide(
                            color: _chatInitialized
                                ? Colors.green
                                : (_isInitializingChat ? Colors.grey : AppColors.accentColor),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _navigateToServiceCenterChat,
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text(
                          'Directions',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accentColor,
                          side: BorderSide(
                            color: AppColors.accentColor,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: widget.onDirections,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Bottom row with Book Service button (full width)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: const Text(
                      'Book Service',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: AppColors.primaryColor.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: widget.onBook,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperatingHourRow(String day, String hours, bool isClosed) {
    final isToday = day == DateFormat('EEEE').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
        isToday
            ? AppColors.primaryColor.withOpacity(0.1)
            : AppColors.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
          isToday
              ? AppColors.primaryColor.withOpacity(0.3)
              : AppColors.borderColor,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isToday)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                day,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                  color:
                  isToday ? AppColors.primaryColor : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (isClosed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.errorColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'CLOSED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Text(
                isClosed ? '' : hours,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                  isClosed ? AppColors.errorColor : AppColors.successColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}