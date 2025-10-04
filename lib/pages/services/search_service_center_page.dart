import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'book_services_page.dart' as book_service_page;
import 'package:automate_application/model/service_center_service_package_offer_model.dart'
    as models;
import 'package:automate_application/pages/services/service_center_details_sheet.dart';

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

  const SearchServiceCenterPage({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
  });

  @override
  State<SearchServiceCenterPage> createState() =>
      _SearchServiceCenterPageState();
}

class _SearchServiceCenterPageState extends State<SearchServiceCenterPage> {
  List<ServiceCenter> serviceCenters = [];
  List<ServiceCenter> filteredCenters = [];
  List<Map<String, dynamic>> serviceCategories = [];
  Map<String, List<String>> serviceCenterCategories = {};
  List<String> selectedFilters = [];
  bool showFilterModal = false;
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
            carOwnerVehicleMake = firstVehicle['make'] ?? '';
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
      final querySnapshot = await FirebaseFirestore.instance
          .collection('service_centers')
          .where('verification.status', isEqualTo: 'approved')
          .get();

      serviceCenters = [];

      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final center = ServiceCenter.fromFirestore(doc.id, data);

          // Load reviews to get actual rating and count
          final reviewsQuery = await FirebaseFirestore.instance
              .collection('reviews')
              .where('serviceCenterId', isEqualTo: center.id)
              .where('status', isEqualTo: 'approved')
              .get();

          // Calculate actual rating from reviews
          if (reviewsQuery.docs.isNotEmpty) {
            double totalRating = 0.0;
            for (var reviewDoc in reviewsQuery.docs) {
              final reviewData = reviewDoc.data();
              totalRating += (reviewData['rating'] as num).toDouble();
            }
            center.rating = totalRating / reviewsQuery.docs.length;
            center.reviewCount = reviewsQuery.docs.length;
          }

          // load the services offer and the packages
          final servicesOffer = await getServicesOfferWithDetails(center.id);
          final packages = await getServicePackages(center.id);

          center.services = servicesOffer.map((service) => service.serviceName).toList();
          center.packages = packages;

          await _loadCenterCategories(center.id);

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

          center.distance = Geolocator.distanceBetween(
            currentPosition!.latitude,
            currentPosition!.longitude,
            lat,
            lng,
          ) / 1000;
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

  Future<void> _loadCenterCategories(String centerId) async {
    try {
      // Get all service offers for this center
      final offersQuery =
          await FirebaseFirestore.instance
              .collection('service_center_services_offer')
              .where('serviceCenterId', isEqualTo: centerId)
              .where('active', isEqualTo: true)
              .get();

      if (offersQuery.docs.isEmpty) {
        serviceCenterCategories[centerId] = [];
        return;
      }

      // Get unique category IDs from the offers
      Set<String> offerCategoryIds = {};
      for (var doc in offersQuery.docs) {
        final categoryId = doc.data()['categoryId'] as String?;
        if (categoryId != null && categoryId.isNotEmpty) {
          offerCategoryIds.add(categoryId);
        }
      }

      if (offerCategoryIds.isEmpty) {
        serviceCenterCategories[centerId] = [];
        return;
      }

      // Get category names for these IDs (batch query for performance)
      List<String> categoryNames = [];
      for (String categoryId in offerCategoryIds) {
        final categoryDoc =
            await FirebaseFirestore.instance
                .collection('services_categories')
                .doc(categoryId)
                .get();

        if (categoryDoc.exists) {
          final categoryName = categoryDoc.data()!['name'] as String?;
          if (categoryName != null) {
            categoryNames.add(categoryName);
          }
        }
      }

      serviceCenterCategories[centerId] = categoryNames;
    } catch (e) {
      debugPrint('Error loading center categories for $centerId: $e');
      serviceCenterCategories[centerId] = [];
    }
  }

  Future<List<models.ServiceOffer>> getServicesOfferWithDetails(
    String centerId,
  ) async {
    try {
      // Get all offers for this service center
      final offersQuery =
          await FirebaseFirestore.instance
              .collection('service_center_services_offer')
              .where('serviceCenterId', isEqualTo: centerId)
              .where('active', isEqualTo: true)
              .get();

      final offers =
          offersQuery.docs
              .map(
                (doc) =>
                    ServiceCenterServiceOffer.fromFirestore(doc.id, doc.data()),
              )
              .toList();

      if (offers.isEmpty) return [];

      // Get unique service IDs
      final serviceOfferIds =
          offers
              .where((offer) => offer.serviceId.isNotEmpty)
              .map((offer) => offer.serviceId)
              .toSet()
              .toList();

      if (serviceOfferIds.isEmpty) return [];

      // Fetch service details in batches (Firestore has a limit of 10 for whereIn)
      final List<Map<String, dynamic>> allServices = [];
      for (int i = 0; i < serviceOfferIds.length; i += 10) {
        final batch = serviceOfferIds.skip(i).take(10).toList();
        final serviceQuery =
            await FirebaseFirestore.instance
                .collection('services')
                .where(FieldPath.documentId, whereIn: batch)
                .get();

        allServices.addAll(
          serviceQuery.docs.map((doc) => {'id': doc.id, ...doc.data()}),
        );
      }

      // Get category names for services
      final categoryIds =
          allServices
              .map((service) => service['categoryId'] as String?)
              .where((id) => id != null && id.isNotEmpty)
              .toSet()
              .toList();

      Map<String, String> categoryNames = {};
      if (categoryIds.isNotEmpty) {
        for (int i = 0; i < categoryIds.length; i += 10) {
          final batch = categoryIds.skip(i).take(10).toList();
          final categoryQuery =
              await FirebaseFirestore.instance
                  .collection('services_categories')
                  .where(FieldPath.documentId, whereIn: batch)
                  .get();

          for (var doc in categoryQuery.docs) {
            categoryNames[doc.id] = doc.data()['name'] ?? '';
          }
        }
      }

      // Create unique services with all details
      final List<models.ServiceOffer> servicesOffer = [];
      for (var service in allServices) {
        final serviceId = service['id'];
        final serviceName = service['name'] ?? '';
        final serviceDescription = service['description'] ?? '';
        final categoryId = service['categoryId'] ?? '';
        final categoryName = categoryNames[categoryId] ?? '';

        // Get all offers for this service
        final serviceOffers =
            offers.where((offer) => offer.serviceId == serviceId).toList();

        servicesOffer.add(
          models.ServiceOffer(
            serviceId: serviceId,
            serviceName: serviceName,
            description: serviceDescription,
            categoryName: categoryName,
            offers: serviceOffers,
          ),
        );
      }

      return servicesOffer;
    } catch (e) {
      debugPrint('Error getting unique services: $e');
      return [];
    }
  }

  Future<List<models.ServicePackage>> getServicePackages(
    String centerId,
  ) async {
    try {
      final packagesQuery =
          await FirebaseFirestore.instance
              .collection('service_packages')
              .where('serviceCenterId', isEqualTo: centerId)
              .where('active', isEqualTo: true)
              .get();

      return packagesQuery.docs
          .map((doc) => models.ServicePackage.fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error getting service packages: $e');
      return [];
    }
  }

  void _filterServiceCenters() {
    filteredCenters =
        serviceCenters.where((center) {
          final matchesSearch =
              center.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              center.city.toLowerCase().contains(searchQuery.toLowerCase()) ||
              center.state.toLowerCase().contains(searchQuery.toLowerCase());

          bool matchesFilter = true;
          if (selectedFilters.isNotEmpty && !selectedFilters.contains('All')) {
            final centerCategories = serviceCenterCategories[center.id] ?? [];

            if (centerCategories.isEmpty) {
              matchesFilter = false;
            } else {
              // Check if center has any of the selected categories
              matchesFilter = selectedFilters.any(
                (selectedFilter) => centerCategories.any(
                  (category) =>
                      category.toLowerCase() == selectedFilter.toLowerCase(),
                ),
              );
            }
          }

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

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildFilterModal(),
    );
  }

  Widget _buildFilterModal() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Column(
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

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filter by Services',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        if (selectedFilters.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedFilters.clear();
                              });
                              setState(() {
                                _filterServiceCenters();
                              });
                            },
                            child: Text(
                              'Clear All',
                              style: TextStyle(color: AppColors.errorColor),
                            ),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Filter Options
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // All option
                    _buildFilterOption(
                      'All',
                      'Show all service centers',
                      Icons.apps_rounded,
                      selectedFilters.isEmpty,
                      () {
                        setModalState(() {
                          selectedFilters.clear();
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // Service Categories
                    if (!categoriesLoading)
                      ...serviceCategories.map((category) {
                        final isSelected = selectedFilters.contains(
                          category['name'],
                        );
                        return _buildFilterOption(
                          category['name'],
                          category['description'] ?? '',
                          _getCategoryIcon(category['name']),
                          isSelected,
                          () {
                            setModalState(() {
                              if (isSelected) {
                                selectedFilters.remove(category['name']);
                              } else {
                                selectedFilters.add(category['name']);
                              }
                            });
                          },
                        );
                      }).toList(),
                  ],
                ),
              ),

              // Apply Button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor,
                  border: Border(top: BorderSide(color: AppColors.borderColor)),
                ),
                child: Column(
                  children: [
                    if (selectedFilters.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${selectedFilters.length} filter${selectedFilters.length == 1 ? '' : 's'} selected',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _filterServiceCenters();
                          });
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(
                          'Apply Filters',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterOption(
    String title,
    String description,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color:
            isSelected
                ? AppColors.primaryColor.withOpacity(0.1)
                : AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                    color: (isSelected
                            ? AppColors.primaryColor
                            : AppColors.textMuted)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color:
                        isSelected
                            ? AppColors.primaryColor
                            : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected
                                  ? AppColors.primaryColor
                                  : AppColors.textPrimary,
                        ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? AppColors.primaryColor
                            : Colors.transparent,
                    shape: BoxShape.circle,
                    border:
                        !isSelected
                            ? Border.all(color: AppColors.borderColor)
                            : null,
                  ),
                  child: Icon(
                    isSelected ? Icons.check : null,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    final name = categoryName.toLowerCase();
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
    if (name.contains('body')) return Icons.brush;
    if (name.contains('electrical')) return Icons.electrical_services;
    if (name.contains('exhaust')) return Icons.air;
    return Icons.build;
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

  Widget _buildStarRating(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: size);
        } else if (index < rating) {
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        } else {
          return Icon(Icons.star_border, color: Colors.grey, size: size);
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

  Future<int> _getReviewCount(String centerId) async {
    try {
      final query =
          await FirebaseFirestore.instance
              .collection('reviews')
              .where('serviceCenterId', isEqualTo: centerId)
              .where('status', isEqualTo: 'approved')
              .get();

      return query.docs.length;
    } catch (e) {
      debugPrint('Error getting review count: $e');
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: AppBar(
          leading: Container(
            margin: const EdgeInsets.all(8),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: Colors.white,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          title: const Text(
            'Find Service Centers',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              shadows: [Shadow(offset: const Offset(0, 2), blurRadius: 4)],
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
                expandedHeight: 160,
                floating: false,
                pinned: true,
                elevation: 0,
                backgroundColor: AppColors.secondaryColor,
                surfaceTintColor: Colors.transparent,
                iconTheme: const IconThemeData(color: Colors.white, size: 24),
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    'Find Service Centers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                          color: Colors.black.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                  centerTitle: true,
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.secondaryColor,
                          AppColors.backgroundColor,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 55),
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
                                  hintText:
                                      'Search by center name or location...',
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
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      child: Material(
                        elevation: selectedFilters.isNotEmpty ? 8 : 2,
                        shadowColor:
                            selectedFilters.isNotEmpty
                                ? AppColors.primaryColor.withOpacity(0.3)
                                : Colors.black.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: _showFilterModal,
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              gradient:
                                  selectedFilters.isNotEmpty
                                      ? LinearGradient(
                                        colors: [
                                          AppColors.primaryColor,
                                          AppColors.primaryColor.withOpacity(
                                            0.8,
                                          ),
                                        ],
                                      )
                                      : null,
                              color:
                                  selectedFilters.isEmpty
                                      ? AppColors.cardColor
                                      : null,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color:
                                    selectedFilters.isNotEmpty
                                        ? Colors.transparent
                                        : AppColors.borderColor,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Icon(
                                    selectedFilters.isNotEmpty
                                        ? Icons.filter_alt_rounded
                                        : Icons.filter_list_rounded,
                                    key: ValueKey(selectedFilters.isNotEmpty),
                                    size: 22,
                                    color:
                                        selectedFilters.isNotEmpty
                                            ? Colors.white
                                            : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Text(
                                    selectedFilters.isEmpty
                                        ? 'Filter Services'
                                        : '${selectedFilters.length} Selected',
                                    key: ValueKey(selectedFilters.length),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: 0.3,
                                      color:
                                          selectedFilters.isNotEmpty
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                if (selectedFilters.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Selected filters preview
                    if (selectedFilters.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: selectedFilters.length,
                            itemBuilder: (context, index) {
                              final filter = selectedFilters[index];
                              return AnimatedContainer(
                                duration: Duration(
                                  milliseconds: 300 + (index * 50),
                                ),
                                curve: Curves.easeOutBack,
                                margin: const EdgeInsets.only(right: 10),
                                child: Material(
                                  elevation: 3,
                                  shadowColor: AppColors.primaryColor
                                      .withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(22),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.primaryColor.withOpacity(
                                            0.15,
                                          ),
                                          AppColors.primaryColor.withOpacity(
                                            0.1,
                                          ),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: AppColors.primaryColor
                                            .withOpacity(0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getCategoryIcon(filter),
                                          size: 14,
                                          color: AppColors.primaryColor,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          filter,
                                          style: TextStyle(
                                            color: AppColors.primaryColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              selectedFilters.remove(filter);
                                              _filterServiceCenters();
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryColor
                                                  .withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 12,
                                              color: AppColors.primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Location Info
            if (currentLocation != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Your Location',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: AppColors.successColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentLocation!,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryColor,
                                AppColors.primaryColor.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${filteredCenters.length} Found',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          '${center.rating.toStringAsFixed(1)}', // Use local state
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' (${center.reviewCount} reviews)', // Use local state
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

                    if (center.services.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Individual Services
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
                                          color: AppColors.primaryColor
                                              .withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
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

                          // Show packages indicator if available
                          if (center.packages.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accentColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.accentColor.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 14,
                                    color: AppColors.accentColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${center.packages.length} Service Packages Available',
                                    style: TextStyle(
                                      color: AppColors.accentColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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
            (context) => book_service_page.BookServicePage(
              userId: widget.userId,
              serviceCenter: center,
            ),
      ),
    );
  }
}