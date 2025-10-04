import 'package:automate_application/pages/services/book_appointment_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:automate_application/model/service_center_services_offer_model.dart';
import 'package:automate_application/model/service_center_service_package_offer_model.dart'
as models;
import 'package:automate_application/model/service_center_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

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

class SearchServicesPage extends StatefulWidget {
  final String userId;
  final String? selectedServiceCenterId;
  final ServiceCenter? selectedServiceCenter;

  const SearchServicesPage({
    super.key,
    required this.userId,
    this.selectedServiceCenterId,
    this.selectedServiceCenter,
  });

  @override
  State<SearchServicesPage> createState() => _SearchServicesPageState();
}

class _SearchServicesPageState extends State<SearchServicesPage> {
  List<Map<String, dynamic>> serviceCategories = [];
  List<ServiceCenter> serviceCenters = [];
  Map<String, List<ServiceCenterServiceOffer>> servicesByCategory = {};
  Map<String, List<models.ServicePackage>> packagesByCategory = {};
  List<ServiceCenterServiceOffer> cartItems = [];
  List<models.ServicePackage> cartPackages = [];
  String? selectedServiceCenterId;
  ServiceCenter? selectedServiceCenter;
  bool categoriesLoading = true;
  bool servicesLoading = false;
  String? expandedCategoryId;
  String selectionType = 'individual'; // 'individual' or 'package'
  String carOwnerVehicleMake = '';
  String carOwnerVehicleModel = '';
  String carOwnerVehicleYear = '';
  String carOwnerVehiclePlateNo = '';
  String carOwnerVehicleDisplacement = '';
  String carOwnerVehicleFuelType = '';
  String carOwnerVehicleSizeClass = '';
  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';
  bool cartHasFixedPricing = false;
  bool cartHasRangePricing = false;
  double cartMinTotal = 0.0;
  double cartMaxTotal = 0.0;

  // Enhanced filter management
  List<String> selectedFilters = [];
  Map<String, bool> categoryExpanded = {};
  bool searchMode = false;
  List<ServiceCenterServiceOffer> filteredServices = [];
  List<models.ServicePackage> filteredPackages = [];

  // Tier and pricing data
  Map<String, Map<String, dynamic>> offerTiers = {};
  Map<String, Map<String, dynamic>> effectivePricing = {};

  @override
  void initState() {
    super.initState();
    selectedServiceCenterId = widget.selectedServiceCenterId;
    selectedServiceCenter = widget.selectedServiceCenter;
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _getUserVehicle();
    await loadAllPackages();
    await loadServiceCategories();
    if (selectedServiceCenterId == null) {
      await _loadServiceCenters();
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

        final activeVehicles =
        vehicles
            .where(
              (vehicle) =>
          (vehicle['status'] ?? '').toString().toLowerCase() ==
              'approved',
        )
            .toList();

        if (activeVehicles.isNotEmpty) {
          final firstVehicle = activeVehicles.first;
          setState(() {
            carOwnerVehicleMake = firstVehicle['make'] ?? '';
            carOwnerVehicleModel = firstVehicle['model'] ?? '';
            carOwnerVehicleYear = firstVehicle['year']?.toString() ?? '';
            carOwnerVehiclePlateNo = firstVehicle['plateNumber'] ?? '';
            carOwnerVehicleDisplacement = _extractDisplacement(
              firstVehicle['displacement'],
            );
            carOwnerVehicleFuelType = firstVehicle['fuelType'] ?? '';
            carOwnerVehicleSizeClass = firstVehicle['sizeClass'] ?? '';
          });
        }
      }
    } catch (err) {
      debugPrint('Error fetching user vehicle: $err');
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

  Future<void> _loadServiceCenters() async {
    try {
      final querySnapshot =
      await FirebaseFirestore.instance
          .collection('service_centers')
          .where('verification.status', isEqualTo: 'approved')
          .get();

      List<ServiceCenter> centers = [];
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data();
          final center = ServiceCenter.fromFirestore(doc.id, data);
          centers.add(center);
        } catch (e) {
          debugPrint("Error processing service center ${doc.id}: $e");
        }
      }

      setState(() {
        serviceCenters = centers;
      });
    } catch (e) {
      debugPrint('Error loading service centers: $e');
    }
  }

  Future<void> _showVehicleSelectionDialog() async {
    // Fetch all user vehicles
    try {
      final doc =
      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      if (!doc.exists) return;

      final data = doc.data()!;
      final vehicles = List<Map<String, dynamic>>.from(data['vehicles'] ?? []);
      final approvedVehicles =
      vehicles.where((v) => (v['status'] ?? '') == 'approved').toList();

      if (!mounted) return;

      if (approvedVehicles.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No approved vehicles found'),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Change Vehicle',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: approvedVehicles.length,
              itemBuilder: (context, index) {
                final vehicle = approvedVehicles[index];
                final isCurrentVehicle =
                    vehicle['plateNumber'] == carOwnerVehiclePlateNo;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color:
                    isCurrentVehicle
                        ? AppColors.primaryColor.withOpacity(0.1)
                        : AppColors.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pop(context);
                        _switchVehicle(vehicle);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                            isCurrentVehicle
                                ? AppColors.primaryColor
                                : AppColors.borderColor,
                            width: isCurrentVehicle ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                'https://cdn.imagin.studio/getImage?customer=demo&make=${vehicle['make']}&modelFamily=${vehicle['model']}&modelYear=${vehicle['year']}&angle=01',
                                height: 60,
                                width: 60,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                    Container(
                                      height: 60,
                                      width: 60,
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceColor,
                                        borderRadius:
                                        BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car,
                                        size: 30,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vehicle['plateNumber'] ?? 'No Plate',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color:
                                      isCurrentVehicle
                                          ? AppColors.primaryColor
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${vehicle['make']} ${vehicle['model']} (${vehicle['year']})',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrentVehicle)
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
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
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading vehicles: $e'),
            backgroundColor: AppColors.errorColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _switchVehicle(Map<String, dynamic> vehicle) async {
    // Validate that the vehicle is approved/active
    String vehicleStatus = (vehicle['status'] ?? '').toString().toLowerCase();
    if (vehicleStatus != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot switch to inactive vehicle (Status: ${vehicle['status']})',
          ),
          backgroundColor: AppColors.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    debugPrint(
      'Switching to vehicle: ${vehicle['make']} ${vehicle['model']} ${vehicle['year']} (${vehicle['status']})',
    );

    setState(() {
      carOwnerVehicleMake = vehicle['make'] ?? '';
      carOwnerVehicleModel = vehicle['model'] ?? '';
      carOwnerVehicleYear = vehicle['year']?.toString() ?? '';
      carOwnerVehiclePlateNo = vehicle['plateNumber'] ?? '';
      carOwnerVehicleDisplacement = _extractDisplacement(
        vehicle['displacement'],
      );
      carOwnerVehicleFuelType = vehicle['fuelType'] ?? '';
      carOwnerVehicleSizeClass = vehicle['sizeClass'] ?? '';

      // Clear cart and cached services since vehicle changed
      cartItems.clear();
      cartPackages.clear();
      selectedServiceCenterId = null;
      selectedServiceCenter = null;
      servicesByCategory.clear();
      packagesByCategory.clear();
      categoryExpanded.clear();
      expandedCategoryId = null;
      offerTiers.clear();
      effectivePricing.clear();
    });

    // Reload packages for the new vehicle
    await loadAllPackages();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${vehicle['make']} ${vehicle['model']}'),
          backgroundColor: AppColors.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> loadAllPackages() async {
    try {
      Query packagesQuery = FirebaseFirestore.instance
          .collection('service_packages')
          .where('active', isEqualTo: true);

      final querySnapshot = await packagesQuery.get();

      List<models.ServicePackage> allPackages = [];
      Map<String, Map<String, dynamic>> tiersMap = {};

      // If we have a selected service center, load its tiers
      if (selectedServiceCenterId != null) {
        final tiersQuery = await FirebaseFirestore.instance
            .collection('service_center_service_tiers')
            .where('serviceCenterId', isEqualTo: selectedServiceCenterId)
            .get();

        for (var tierDoc in tiersQuery.docs) {
          tiersMap[tierDoc.id] = tierDoc.data() as Map<String, dynamic>;
        }
      }

      // Collect all service center IDs first
      Set<String> serviceCenterIds = {};
      Map<String, models.ServicePackage> tempPackages = {};

      for (var doc in querySnapshot.docs) {
        try {
          final packageData = doc.data() as Map<String, dynamic>;
          final isActive = packageData['active'] == true;
          if (!isActive) continue;

          final package = models.ServicePackage.fromFirestore(doc.id, packageData);

          // Check package compatibility
          bool isCompatible = await _checkPackageCompatibilityWithActiveOffers(
            package.id,
            tiersMap,
          );

          if (isCompatible) {
            allPackages.add(package);
            tempPackages[doc.id] = package;

            // Collect service center ID for lookup
            if (package.serviceCenterId.isNotEmpty) {
              serviceCenterIds.add(package.serviceCenterId);
            }
          }
        } catch (e) {
          debugPrint('Error parsing package ${doc.id}: $e');
        }
      }

      // Batch load all service center names
      if (serviceCenterIds.isNotEmpty) {
        final serviceCentersQuery = await FirebaseFirestore.instance
            .collection('service_centers')
            .where(FieldPath.documentId, whereIn: serviceCenterIds.toList())
            .get();

        Map<String, String> serviceCenterNames = {};
        for (var centerDoc in serviceCentersQuery.docs) {
          final centerData = centerDoc.data();
          final name = centerData['serviceCenterInfo']?['name'] ?? centerDoc.id;
          serviceCenterNames[centerDoc.id] = name;
        }

        // Assign service center names to packages
        for (var package in allPackages) {
          if (package.serviceCenterId.isNotEmpty) {
            package.serviceCenterName = serviceCenterNames[package.serviceCenterId] ?? package.serviceCenterId;
          }
        }
      }

      setState(() {
        packagesByCategory['all_packages'] = allPackages;
      });
    } catch (e) {
      debugPrint('Error loading all packages: $e');
      setState(() {
        packagesByCategory['all_packages'] = [];
      });
    }
  }

  Future<bool> _checkPackageCompatibilityWithActiveOffers(
      String packageId,
      Map<String, Map<String, dynamic>> tiersMap,
      ) async {
    try {
      if (carOwnerVehicleMake.isEmpty ||
          carOwnerVehicleModel.isEmpty ||
          carOwnerVehicleYear.isEmpty) {
        return false;
      }

      // Get ONLY active service offers that belong to this package
      Query packageOffersQuery = FirebaseFirestore.instance
          .collection('service_center_services_offer')
          .where('servicePackageId', isEqualTo: packageId)
          .where('active', isEqualTo: true);

      if (selectedServiceCenterId != null) {
        packageOffersQuery = packageOffersQuery.where(
          'serviceCenterId',
          isEqualTo: selectedServiceCenterId,
        );
      }

      final packageOffersSnapshot = await packageOffersQuery.get();

      if (packageOffersSnapshot.docs.isEmpty) {
        return false;
      }

      String vehicleMake = _normalize(carOwnerVehicleMake);
      String vehicleModel = _normalize(carOwnerVehicleModel);
      String vehicleYear = carOwnerVehicleYear;
      String vehicleFuelType = _normalize(carOwnerVehicleFuelType);
      String vehicleDisplacement = carOwnerVehicleDisplacement;
      String vehicleSizeClass = _normalize(carOwnerVehicleSizeClass);

      // CRITICAL FIX: Load all required tiers for this package's offers
      Set<String> requiredTierIds = {};
      for (var offerDoc in packageOffersSnapshot.docs) {
        final offerData = offerDoc.data() as Map<String, dynamic>;
        final tierIdValue = offerData['tierId'];
        if (tierIdValue != null && tierIdValue.toString().isNotEmpty) {
          requiredTierIds.add(tierIdValue.toString());
        }
      }

      // Load missing tier data
      Map<String, Map<String, dynamic>> completeTiersMap = Map.from(tiersMap);
      if (requiredTierIds.isNotEmpty) {
        for (String tierId in requiredTierIds) {
          if (!completeTiersMap.containsKey(tierId)) {
            try {
              final tierDoc =
              await FirebaseFirestore.instance
                  .collection('service_center_service_tiers')
                  .doc(tierId)
                  .get();

              if (tierDoc.exists) {
                completeTiersMap[tierId] =
                tierDoc.data() as Map<String, dynamic>;
              }
            } catch (e) {
              debugPrint('Error loading tier $tierId: $e');
            }
          }
        }
      }

      // Check each active service offer in the package
      int compatibleOffers = 0;
      for (var offerDoc in packageOffersSnapshot.docs) {
        try {
          final offerData = offerDoc.data() as Map<String, dynamic>;

          // Triple-check that the offer is active (should already be filtered, but being safe)
          final isOfferActive = offerData['active'] == true;
          if (!isOfferActive) {
            continue;
          }

          final offer = ServiceCenterServiceOffer.fromFirestore(
            offerDoc.id,
            offerData,
          );

          bool isOfferCompatible = false;

          // FIXED: Check with tier if available - now using completeTiersMap
          if (offer.tierId != null &&
              offer.tierId!.isNotEmpty &&
              completeTiersMap.containsKey(offer.tierId)) {
            final tierData = completeTiersMap[offer.tierId!]!;

            isOfferCompatible = _checkVehicleCompatibilityWithTier(
              tierData,
              vehicleMake,
              vehicleModel,
              vehicleYear,
              vehicleFuelType,
              vehicleDisplacement,
              vehicleSizeClass,
            );
          } else if (offer.tierId != null && offer.tierId!.isNotEmpty) {
            isOfferCompatible = false;
          } else {
            // Check with offer's own compatibility data
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
            compatibleOffers++;
          }
        } catch (e) {
          debugPrint(
            'Error checking compatibility for offer ${offerDoc.id}: $e',
          );
        }
      }

      // Package is compatible if it has at least one compatible active offer
      bool packageIsCompatible = compatibleOffers > 0;

      return packageIsCompatible;
    } catch (e) {
      debugPrint('Error checking package compatibility for $packageId: $e');
      return false;
    }
  }

  Future<void> loadServiceCategories() async {
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

  Future<void> loadServicesForCategory(String categoryId) async {
    if (servicesByCategory.containsKey(categoryId)) {
      return;
    }

    setState(() => servicesLoading = true);

    try {
      Query individualServicesQuery = FirebaseFirestore.instance
          .collection('service_center_services_offer')
          .where('categoryId', isEqualTo: categoryId)
          .where('active', isEqualTo: true);

      // if (selectedServiceCenterId != null) {
      //   individualServicesQuery = individualServicesQuery.where(
      //     'serviceCenterId',
      //     isEqualTo: selectedServiceCenterId,
      //   );
      // }

      final querySnapshot = await individualServicesQuery.get();

      // Load tiers for pricing
      Query tiersQuery = FirebaseFirestore.instance.collection(
        'service_center_service_tiers',
      );

      if (selectedServiceCenterId != null) {
        tiersQuery = tiersQuery.where(
          'serviceCenterId',
          isEqualTo: selectedServiceCenterId,
        );
      }

      final tiersSnapshot = await tiersQuery.get();
      Map<String, Map<String, dynamic>> tiersMap = {};
      for (var tierDoc in tiersSnapshot.docs) {
        tiersMap[tierDoc.id] = tierDoc.data() as Map<String, dynamic>;
      }

      List<ServiceCenterServiceOffer> compatibleServices = [];

      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;

          // Double-check that the service offer is active
          final isOfferActive = data['active'] == true;
          if (!isOfferActive) {
            continue;
          }

          final service = ServiceCenterServiceOffer.fromFirestore(doc.id, data);

          // Apply same compatibility logic as packages
          bool isCompatible = _checkServiceCompatibility(service, tiersMap);
          if (isCompatible) {
            await _loadServiceName(service);
            compatibleServices.add(service);
          }
        } catch (e) {
          debugPrint('Error parsing service ${doc.id}: $e');
        }
      }

      setState(() {
        servicesByCategory[categoryId] = compatibleServices;
        servicesLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading services for category $categoryId: $e');
      setState(() => servicesLoading = false);
    }
  }

  bool _checkServiceCompatibility(
      ServiceCenterServiceOffer service,
      Map<String, Map<String, dynamic>> tiersMap,
      ) {
    String vehicleMake = _normalize(carOwnerVehicleMake);
    String vehicleModel = _normalize(carOwnerVehicleModel);
    String vehicleYear = carOwnerVehicleYear;
    String vehicleFuelType = _normalize(carOwnerVehicleFuelType);
    String vehicleDisplacement = carOwnerVehicleDisplacement;
    String vehicleSizeClass = _normalize(carOwnerVehicleSizeClass);

    // Check with tier if available
    if (service.tierId != null && tiersMap.containsKey(service.tierId)) {
      final tierData = tiersMap[service.tierId!]!;
      bool isCompatible = _checkVehicleCompatibilityWithTier(
        tierData,
        vehicleMake,
        vehicleModel,
        vehicleYear,
        vehicleFuelType,
        vehicleDisplacement,
        vehicleSizeClass,
      );

      if (isCompatible) {
        offerTiers[service.id] = tierData;
        _setEffectivePricing(service.id, tierData, service);
      }

      return isCompatible;
    } else {
      return _checkVehicleCompatibilityWithOffer(
        service,
        vehicleMake,
        vehicleModel,
        vehicleYear,
        vehicleFuelType,
        vehicleDisplacement,
        vehicleSizeClass,
      );
    }
  }

  void _setEffectivePricing(
      String offerId,
      Map<String, dynamic> tierData,
      ServiceCenterServiceOffer service,
      ) {
    Map<String, dynamic> pricing = {};
    pricing['price'] = tierData['price'] ?? service.partPrice;
    pricing['priceMin'] = tierData['priceMin'] ?? service.partPriceMin;
    pricing['priceMax'] = tierData['priceMax'] ?? service.partPriceMax;
    pricing['labourPrice'] = tierData['labourPrice'] ?? service.labourPrice;
    pricing['labourPriceMin'] =
        tierData['labourPriceMin'] ?? service.labourPriceMin;
    pricing['labourPriceMax'] =
        tierData['labourPriceMax'] ?? service.labourPriceMax;
    pricing['duration'] = tierData['duration'] ?? service.duration;
    effectivePricing[offerId] = pricing;
  }

  String _normalize(String s) => s.toLowerCase().trim();

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

  Future<void> _loadServiceName(ServiceCenterServiceOffer service) async {
    try {
      if (service.serviceId!.isNotEmpty) {
        final serviceDoc =
        await FirebaseFirestore.instance
            .collection('services')
            .doc(service.serviceId)
            .get();

        if (serviceDoc.exists) {
          final serviceData = serviceDoc.data()!;
          service.serviceName =
              serviceData['name'] ?? service.serviceDescription;
        }
      }

      if (service.serviceCenterId.isNotEmpty) {
        final centerDoc =
        await FirebaseFirestore.instance
            .collection('service_centers')
            .doc(service.serviceCenterId)
            .get();

        if (centerDoc.exists) {
          final centerData = centerDoc.data()!;
          service.serviceCenterName =
              centerData['serviceCenterInfo']?['name'] ??
                  service.serviceCenterId;
        }
      }
    } catch (e) {
      debugPrint('Error loading service name for ${service.id}: $e');
    }
  }

  void _performSearch() {
    if (searchQuery.isEmpty) {
      setState(() {
        searchMode = false;
        filteredServices.clear();
        filteredPackages.clear();
      });
      return;
    }

    setState(() {
      searchMode = true;
      filteredServices.clear();
      filteredPackages.clear();
    });

    final query = searchQuery.toLowerCase();

    // Search in services
    for (var services in servicesByCategory.values) {
      for (var service in services) {
        if (service.serviceName?.toLowerCase().contains(query) == true ||
            service.serviceDescription.toLowerCase().contains(query)) {
          filteredServices.add(service);
        }
      }
    }

    // Search in packages
    for (var packages in packagesByCategory.values) {
      for (var package in packages) {
        if (package.name.toLowerCase().contains(query) ||
            package.description.toLowerCase().contains(query)) {
          filteredPackages.add(package);
        }
      }
    }

    setState(() {});
  }

  void _addToCart(ServiceCenterServiceOffer service) {
    // Check if cart is empty or from same service center
    if ((cartItems.isNotEmpty || cartPackages.isNotEmpty) &&
        selectedServiceCenterId != service.serviceCenterId) {
      _showServiceCenterMismatchDialog();
      return;
    }

    // Check if service already in cart
    if (cartItems.any((item) => item.id == service.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This service is already in your cart'),
          backgroundColor: AppColors.primaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      cartItems.add(service);
      selectedServiceCenterId = service.serviceCenterId;
    });

    if (selectedServiceCenter == null) {
      _loadServiceCenterInfo(service.serviceCenterId);
      selectionType = 'individual';
    }

    if (selectedServiceCenter == null || selectedServiceCenter!.id != service.serviceCenterId) {
      _loadServiceCenterInfo(service.serviceCenterId);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${service.serviceName} added to cart'),
        backgroundColor: AppColors.successColor,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW CART',
          textColor: AppColors.cardColor,
          onPressed: _showCart,
        ),
      ),
    );
  }

  void _addPackageToCart(models.ServicePackage package) async {
    // Check if cart is empty or from same service center
    if ((cartItems.isNotEmpty || cartPackages.isNotEmpty) &&
        selectedServiceCenterId != package.serviceCenterId) {
      _showServiceCenterMismatchDialog();
      return;
    }

    // Check if package already in cart
    if (cartPackages.any((item) => item.id == package.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('This package is already in your cart'),
          backgroundColor: AppColors.primaryColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      cartPackages.add(package);
      selectedServiceCenterId = package.serviceCenterId;
      selectionType = 'package';
    });

    if (selectedServiceCenter == null || selectedServiceCenter!.id != package.serviceCenterId) {
      await _loadServiceCenterInfo(package.serviceCenterId);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${package.name} package added to cart'),
        backgroundColor: AppColors.successColor,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VIEW CART',
          textColor: AppColors.cardColor,
          onPressed: _showCart,
        ),
      ),
    );
  }

  Future<void> _loadServiceCenterInfo(String serviceCenterId) async {
    try {
      final doc =
      await FirebaseFirestore.instance
          .collection('service_centers')
          .doc(serviceCenterId)
          .get();

      if (doc.exists) {
        setState(() {
          selectedServiceCenter = ServiceCenter.fromFirestore(
            doc.id,
            doc.data()!,
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading service center info: $e');
    }
  }

  void _showServiceCenterMismatchDialog() {
    String currentServiceCenterName = selectedServiceCenter?.name ?? 'another service center';
    int totalItems = cartItems.length + cartPackages.length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warningColor,
            ),
            const SizedBox(width: 8),
            const Flexible(child: Text('Different Service Center')),
          ],
        ),
        content: Text(
          'You currently have $totalItems item(s) from $currentServiceCenterName. '
              'You can only book services from one service center at a time. '
              'Would you like to clear your current cart and add this item?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                cartItems.clear();
                cartPackages.clear();
                selectedServiceCenterId = null;
                selectedServiceCenter = null;
              });
            },
            child: const Text('Clear Cart'),
          ),
        ],
      ),
    );
  }

  void _showCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildCartBottomSheet(),
    );
  }

  Future<Map<String, dynamic>> _calculateTotalPriceWithDetails() async {
    double total = 0.0;
    double minTotal = 0.0;
    double maxTotal = 0.0;
    bool hasFixedPricing = false;
    bool hasRangePricing = false;

    // Calculate services total
    for (var service in cartItems) {
      final serviceDetails = _calculateServicePriceDetails(service);
      total += serviceDetails['total'] ?? 0.0;
      minTotal += serviceDetails['minTotal'] ?? 0.0;
      maxTotal += serviceDetails['maxTotal'] ?? 0.0;
      hasFixedPricing = hasFixedPricing || serviceDetails['hasFixedPricing'] == true;
      hasRangePricing = hasRangePricing || serviceDetails['hasRangePricing'] == true;
    }

    // Calculate packages total
    for (var package in cartPackages) {
      final packageDetails = await _calculatePackagePriceDetails(package);
      total += packageDetails['total'] ?? 0.0;
      minTotal += packageDetails['minTotal'] ?? 0.0;
      maxTotal += packageDetails['maxTotal'] ?? 0.0;
      hasFixedPricing = hasFixedPricing || packageDetails['hasFixedPricing'] == true;
      hasRangePricing = hasRangePricing || packageDetails['hasRangePricing'] == true;
    }

    return {
      'total': total,
      'minTotal': minTotal,
      'maxTotal': maxTotal,
      'hasFixedPricing': hasFixedPricing,
      'hasRangePricing': hasRangePricing,
    };
  }

  Map<String, dynamic> _calculateServicePriceDetails(ServiceCenterServiceOffer service) {
    final effectivePricing = this.effectivePricing[service.id];

    double partPrice = effectivePricing?['price'] ?? service.partPrice;
    double labourPrice = effectivePricing?['labourPrice'] ?? service.labourPrice;
    double partPriceMin = effectivePricing?['priceMin'] ?? service.partPriceMin;
    double partPriceMax = effectivePricing?['priceMax'] ?? service.partPriceMax;
    double labourPriceMin = effectivePricing?['labourPriceMin'] ?? service.labourPriceMin;
    double labourPriceMax = effectivePricing?['labourPriceMax'] ?? service.labourPriceMax;

    bool hasFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasRangePricing = partPriceMin > 0 || partPriceMax > 0 || labourPriceMin > 0 || labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    // Calculate total using the same logic as before
    double total;
    if (hasFixedPricing && hasRangePricing && maxTotal > 0) {
      total = fixedTotal + maxTotal; // Conservative estimate for cart
    } else if (hasFixedPricing && !hasRangePricing) {
      total = fixedTotal;
    } else if (hasRangePricing && (minTotal > 0 || maxTotal > 0)) {
      total = maxTotal;
    } else {
      total = 0.0;
    }

    return {
      'total': total,
      'minTotal': fixedTotal + minTotal,
      'maxTotal': fixedTotal + maxTotal,
      'hasFixedPricing': hasFixedPricing,
      'hasRangePricing': hasRangePricing,
    };
  }

  Future<Map<String, dynamic>> _calculatePackagePriceDetails(models.ServicePackage package) async {
    // Use fixed price if available
    if (package.fixedPrice != null && package.fixedPrice! > 0) {
      return {
        'total': package.fixedPrice!,
        'minTotal': package.fixedPrice!,
        'maxTotal': package.fixedPrice!,
        'hasFixedPricing': true,
        'hasRangePricing': false,
      };
    }

    final packagePricing = await _calculatePackagePricing(package);

    double partPrice = packagePricing['totalPartPrice'] ?? 0.0;
    double labourPrice = packagePricing['totalLabourPrice'] ?? 0.0;
    double partPriceMin = packagePricing['minPartPrice'] ?? 0.0;
    double partPriceMax = packagePricing['maxPartPrice'] ?? 0.0;
    double labourPriceMin = packagePricing['minLabourPrice'] ?? 0.0;
    double labourPriceMax = packagePricing['maxLabourPrice'] ?? 0.0;

    bool hasFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasRangePricing = partPriceMin > 0 || partPriceMax > 0 || labourPriceMin > 0 || labourPriceMax > 0;

    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    // Calculate total using consistent logic
    double total;
    if (hasFixedPricing && hasRangePricing && maxTotal > 0) {
      total = fixedTotal + maxTotal;
    } else if (hasFixedPricing && !hasRangePricing) {
      total = fixedTotal;
    } else if (hasRangePricing && (minTotal > 0 || maxTotal > 0)) {
      total = maxTotal;
    } else {
      total = 0.0;
    }

    return {
      'total': total,
      'minTotal': fixedTotal + minTotal,
      'maxTotal': fixedTotal + maxTotal,
      'hasFixedPricing': hasFixedPricing,
      'hasRangePricing': hasRangePricing,
    };
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
                      'Filter by Categories',
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
                  children:
                  serviceCategories.map((category) {
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
                ),
              ),

              // Apply Button
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor,
                  border: Border(top: BorderSide(color: AppColors.borderColor)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {});
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
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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

  void _proceedToAppointment() async {
    final Map<String, dynamic> pricingDetails = await _calculateTotalPriceWithDetails();
    int totalDuration = await _calculateTotalDuration();

    Map<String, int> packageDurations = {};
    Map<String, Map<String, dynamic>> packagePricing = {};
    for (var package in cartPackages) {
      final pricing = await _calculatePackagePricing(package);
      int packageDuration = (pricing['duration'] ?? package.estimatedDuration).toInt();
      packageDurations[package.id] = packageDuration;

      packagePricing[package.id] = {
        'fixedPrice': pricing['totalPartPrice'] + pricing['totalLabourPrice'],
        'minPrice': pricing['minPartPrice'] + pricing['minLabourPrice'],
        'maxPrice': pricing['maxPartPrice'] + pricing['maxLabourPrice'],
      };
    }

    for (var service in cartItems) {
      final effectivePricing = this.effectivePricing[service.id];
      int duration = effectivePricing?['duration'] ?? service.duration;
    }

    for (var package in cartPackages) {
      final packagePricing = await _calculatePackagePricing(package);
      int packageDuration = packagePricing['duration'] ?? package.estimatedDuration;
      debugPrint('Package: ${package.name} - Duration: $packageDuration min');
    }

    // Calculate total pricing including both services and packages
    double totalFixedPrice = pricingDetails['total'] ?? 0.0;
    String totalRangePrice = _getTotalRangePriceDisplay(pricingDetails);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookAppointmentPage(
          userId: widget.userId,
          serviceCenter: selectedServiceCenter!,
          services: cartItems,
          packages: cartPackages,
          selectionType: selectionType,
          selectedVehiclePlateNo: carOwnerVehiclePlateNo,
          totalEstimatedDuration: totalDuration,
          totalFixedPrice: totalFixedPrice,
          totalRangePrice: totalRangePrice,
          packageDurations: packageDurations,
          packagePricing: packagePricing,
        ),
      ),
    );
  }

  Future<int> _calculateTotalDuration() async {
    int totalDuration = 0;

    // Calculate services duration
    for (var service in cartItems) {
      final effectivePricing = this.effectivePricing[service.id];
      int duration = effectivePricing?['duration'] ?? service.duration;
      totalDuration += duration;
    }

    // Calculate packages duration - FIX: Use async calculation
    for (var package in cartPackages) {
      final packagePricing = await _calculatePackagePricing(package);
      // FIX: Convert the duration to int since it might come as num from Firestore
      int packageDuration = (packagePricing['duration'] ?? package.estimatedDuration).toInt();
      totalDuration += packageDuration;
    }

    return totalDuration;
  }

  String _getTotalRangePriceDisplay(Map<String, dynamic> pricingDetails) {
    double minTotal = pricingDetails['minTotal'] ?? 0.0;
    double maxTotal = pricingDetails['maxTotal'] ?? 0.0;
    bool hasRangePricing = pricingDetails['hasRangePricing'] ?? false;

    if (hasRangePricing && maxTotal > minTotal) {
      return 'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}';
    }
    return '';
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 230,
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
            actions: [
              // Cart button with badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                child: Stack(
                  children: [
                    IconButton(
                      onPressed: _showCart,
                      icon: const Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    if (cartItems.isNotEmpty || cartPackages.isNotEmpty)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: AppColors.errorColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '${cartItems.length + cartPackages.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.secondaryColor,
                      AppColors.secondaryColor.withOpacity(0.8),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Vehicle Info Card
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.cardColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.cardColor.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child:
                                (carOwnerVehicleMake.isNotEmpty &&
                                    carOwnerVehicleModel
                                        .isNotEmpty &&
                                    carOwnerVehicleYear.isNotEmpty)
                                    ? Image.network(
                                  'https://cdn.imagin.studio/getImage?customer=demo&make=$carOwnerVehicleMake&modelFamily=$carOwnerVehicleModel&modelYear=$carOwnerVehicleYear&angle=01',
                                  height: 100,
                                  width: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (
                                      context,
                                      error,
                                      stackTrace,
                                      ) => Container(
                                    height: 60,
                                    width: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.white
                                          .withOpacity(0.2),
                                      borderRadius:
                                      BorderRadius.circular(
                                        12,
                                      ),
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
                                    color: AppColors.cardColor
                                        .withOpacity(0.2),
                                    borderRadius:
                                    BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.directions_car,
                                    size: 30,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      carOwnerVehiclePlateNo.isNotEmpty
                                          ? carOwnerVehiclePlateNo
                                          : 'No Vehicle',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (carOwnerVehicleMake.isNotEmpty &&
                                        carOwnerVehicleModel
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '$carOwnerVehicleMake $carOwnerVehicleModel${carOwnerVehicleYear.isNotEmpty ? ' ($carOwnerVehicleYear)' : ''}',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(
                                            0.9,
                                          ),
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryColor,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                onPressed: _showVehicleSelectionDialog,
                                tooltip: 'Switch Vehicle',
                              ),
                            ],
                          ),
                        ),

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
                              hintText: 'Search services and packages...',
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
                                    searchMode = false;
                                    filteredServices.clear();
                                    filteredPackages.clear();
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
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() {
                                searchQuery = value;
                              });
                              _performSearch();
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
            // Service Type Toggle and Filter Button
            Container(
              margin: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Service Type Toggle
                  Expanded(
                    child: Container(
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
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                  selectionType == 'individual'
                                      ? AppColors.primaryColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Services',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                    selectionType == 'individual'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
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
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                  selectionType == 'package'
                                      ? AppColors.primaryColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Packages',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color:
                                    selectionType == 'package'
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Filter Button
                  Material(
                    elevation: selectedFilters.isNotEmpty ? 4 : 2,
                    shadowColor:
                    selectedFilters.isNotEmpty
                        ? AppColors.primaryColor.withOpacity(0.3)
                        : Colors.black.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _showFilterModal,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                          selectedFilters.isNotEmpty
                              ? AppColors.primaryColor
                              : AppColors.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                            selectedFilters.isNotEmpty
                                ? Colors.transparent
                                : AppColors.borderColor,
                          ),
                        ),
                        child: Icon(
                          Icons.filter_list_rounded,
                          color:
                          selectedFilters.isNotEmpty
                              ? Colors.white
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child:
              searchMode
                  ? _buildSearchResults()
                  : _buildCategorizedContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (filteredServices.isEmpty && filteredPackages.isEmpty) {
      return Center(
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
                size: 36,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No results found',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different search terms',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (selectionType == 'individual' && filteredServices.isNotEmpty) ...[
          Text(
            'Services (${filteredServices.length})',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...filteredServices
              .map((service) => _buildServiceCard(service))
              .toList(),
        ],
        if (selectionType == 'package' && filteredPackages.isNotEmpty) ...[
          Text(
            'Packages (${filteredPackages.length})',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ...filteredPackages
              .map((package) => _buildPackageCard(package))
              .toList(),
        ],
      ],
    );
  }

  Widget _buildCategorizedContent() {
    if (categoriesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    if (selectionType == 'package') {
      return _buildPackagesList();
    }

    if (serviceCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 20),
            Text(
              'No categories available',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Filter categories based on selected filters
    final categoriesToShow =
    selectedFilters.isEmpty
        ? serviceCategories
        : serviceCategories
        .where((category) => selectedFilters.contains(category['name']))
        .toList();

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: categoriesToShow.length,
      itemBuilder: (context, index) {
        final category = categoriesToShow[index];
        return _buildCategoryCard(category);
      },
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final categoryId = category['id'];
    final isExpanded = categoryExpanded[categoryId] ?? false;
    final hasData = servicesByCategory.containsKey(categoryId);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              if (!hasData) {
                await loadServicesForCategory(categoryId);
              }
              setState(() {
                categoryExpanded[categoryId] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                      _getCategoryIcon(category['name']) == Icons.build
                          ? AppColors.primaryColor.withOpacity(0.1)
                          : _getServiceColor(
                        category['name'],
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getCategoryIcon(category['name']),
                      color:
                      _getCategoryIcon(category['name']) == Icons.build
                          ? AppColors.primaryColor
                          : _getServiceColor(category['name']),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category['name'],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (category['description'].isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            category['description'],
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (servicesLoading && expandedCategoryId == categoryId)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                      ),
                    )
                  else
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (isExpanded && hasData) _buildCategoryContent(categoryId),
        ],
      ),
    );
  }

  Widget _buildPackagesList() {
    final allPackages = packagesByCategory['all_packages'] ?? [];

    if (allPackages.isEmpty) {
      return Center(
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
                Icons.inventory_2_outlined,
                size: 64,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No packages available',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedServiceCenterId != null
                  ? 'This service center has no packages'
                  : 'No packages found',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Available Packages (${allPackages.length})',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a service package',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        ...allPackages.map((package) => _buildPackageCard(package)).toList(),
      ],
    );
  }

  Widget _buildCategoryContent(String categoryId) {
    final services = servicesByCategory[categoryId] ?? [];
    final allPackages = packagesByCategory['all_packages'] ?? [];

    if (selectionType == 'individual' && services.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No services available for your vehicle in this category',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    if (selectionType == 'package' && allPackages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No packages available for your vehicle',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          if (selectionType == 'individual' && services.isNotEmpty)
            ...services.map((service) => _buildServiceCard(service)).toList(),
          if (selectionType == 'package' && allPackages.isNotEmpty)
            ...allPackages
                .map((package) => _buildPackageCard(package))
                .toList(),
        ],
      ),
    );
  }

  Widget _buildServiceCard(ServiceCenterServiceOffer service) {
    final effectivePricing = this.effectivePricing[service.id];
    final isInCart = cartItems.any((item) => item.id == service.id);

    return Container(
      margin: const EdgeInsets.all(8),
      child: Card(
        color: AppColors.surfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service Header with Icon and Details
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Icon
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _getServiceColor(
                        service.serviceName ?? '',
                      ).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _getServiceIcon(service.serviceName ?? ''),
                      color: _getServiceColor(service.serviceName ?? ''),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Service Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Service Name
                        Text(
                          service.serviceName ?? 'Unknown Service',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                            height: 1.3,
                          ),
                        ),

                        // Service Description
                        if (service.serviceDescription.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            service.serviceDescription,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        // Service Center Name
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.store_outlined,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                service.serviceCenterName ??
                                    service.serviceCenterId,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Divider
              Divider(height: 1, thickness: 1, color: AppColors.borderColor),

              const SizedBox(height: 16),

              // Price and Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildPriceInfo(service, effectivePricing)),
                  const SizedBox(width: 16),

                  // Add to Cart Button
                  ElevatedButton.icon(
                    onPressed: isInCart ? null : () => _addToCart(service),
                    icon: Icon(
                      isInCart ? Icons.check_circle : Icons.add_shopping_cart,
                      size: 18,
                    ),
                    label: Text(
                      isInCart ? 'Added' : 'Add',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      isInCart
                          ? AppColors.successColor
                          : AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: isInCart ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageCard(models.ServicePackage package) {
    final isInCart = cartPackages.any((item) => item.id == package.id);

    return Container(
      margin: const EdgeInsets.all(12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Package Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
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
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
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
                        const SizedBox(height: 4),
                        Icon(
                          Icons.store_outlined,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        if (package.serviceCenterName != null && package.serviceCenterName!.isNotEmpty)
                          Text(
                            package.serviceCenterName!,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Package Description
              Text(
                package.description,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 16),

              if (package.services.isNotEmpty) ...[
                Text(
                  'Includes:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: package.services.map(
                        (service) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.1),
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
                  ).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Price and Action Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _buildPackagePriceInfo(package)),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: isInCart ? null : () => _addPackageToCart(package),
                    icon: Icon(
                      isInCart ? Icons.check_circle : Icons.add_shopping_cart,
                      size: 18,
                    ),
                    label: Text(
                      isInCart ? 'Added' : 'Add',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isInCart
                          ? AppColors.successColor
                          : AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      elevation: isInCart ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceInfo(
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
    int duration = effectivePricing?['duration'] ?? service.duration;

    // Check if we have any fixed pricing (either parts OR labour, not necessarily both)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // If both fixed and range pricing exist - FIXED: Show proper range from min to max
        if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warningColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Parts: RM${partPrice.toStringAsFixed(2)}${partPriceMin > 0 || partPriceMax > 0 ? ' (+RM${partPriceMin.toStringAsFixed(2)}-RM${partPriceMax.toStringAsFixed(2)})' : ''} | Labour: RM${labourPrice.toStringAsFixed(2)}${labourPriceMin > 0 || labourPriceMax > 0 ? ' (+RM${labourPriceMin.toStringAsFixed(2)}-RM${labourPriceMax.toStringAsFixed(2)})' : ''}',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          )
        // If only fixed pricing exists (at least one component has a price)
        else if (hasAnyFixedPricing && !hasAnyRangePricing)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RM${fixedTotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.successColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Parts: RM${partPrice.toStringAsFixed(2)} | Labour: RM${labourPrice.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          )
        // If only range pricing exists
        else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.warningColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Parts: RM${partPriceMin.toStringAsFixed(2)}-${partPriceMax.toStringAsFixed(2)} | Labour: RM${labourPriceMin.toStringAsFixed(2)}-${labourPriceMax.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            )
          // Fallback - no pricing available
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RM0.00',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Parts: RM${partPrice.toStringAsFixed(2)} | Labour: RM${labourPrice.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.schedule, size: 16, color: AppColors.accentColor),
            const SizedBox(width: 4),
            Text(
              '${duration} min',
              style: TextStyle(
                color: AppColors.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<Map<String, dynamic>> _calculatePackagePricing(models.ServicePackage package) async {
    double totalPartPrice = 0.0;
    double totalLabourPrice = 0.0;
    double totalPartPriceMin = 0.0;
    double totalPartPriceMax = 0.0;
    double totalLabourPriceMin = 0.0;
    double totalLabourPriceMax = 0.0;
    int totalDuration = 0;
    bool hasAllFixedPrices = true;
    int validOffers = 0;

    try {
      // String serviceCenterToUse = selectedServiceCenterId ?? package.serviceCenterId;

      // Get ONLY ACTIVE service offers for this package
      final packageOffersQuery = await FirebaseFirestore.instance
          .collection('service_center_services_offer')
          .where('servicePackageId', isEqualTo: package.id)
          .where('active', isEqualTo: true)
          // .where('serviceCenterId', isEqualTo: serviceCenterToUse)
          .get();

      Set<String> requiredTierIds = {};
      for (var offerDoc in packageOffersQuery.docs) {
        final offerData = offerDoc.data();
        final tierIdValue = offerData['tierId'];
        if (tierIdValue != null && tierIdValue.toString().isNotEmpty) {
          requiredTierIds.add(tierIdValue.toString());
        }
      }

      // Load tier data dynamically
      Map<String, Map<String, dynamic>> tiersMap = {};
      if (requiredTierIds.isNotEmpty) {
        for (String tierId in requiredTierIds) {
          try {
            final tierDoc = await FirebaseFirestore.instance
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

      for (var offerDoc in packageOffersQuery.docs) {
        final offerData = offerDoc.data();

        // Triple-check that the offer is active
        final isOfferActive = offerData['active'] == true;
        if (!isOfferActive) {
          continue;
        }

        final offer = ServiceCenterServiceOffer.fromFirestore(
          offerDoc.id,
          offerData,
        );

        // Check compatibility first
        String vehicleMake = _normalize(carOwnerVehicleMake);
        String vehicleModel = _normalize(carOwnerVehicleModel);
        String vehicleYear = carOwnerVehicleYear;
        String vehicleFuelType = _normalize(carOwnerVehicleFuelType);
        String vehicleDisplacement = carOwnerVehicleDisplacement;
        String vehicleSizeClass = _normalize(carOwnerVehicleSizeClass);

        bool isOfferCompatible = false;
        Map<String, dynamic>? effectivePricing;

        if (offer.tierId != null && offer.tierId!.isNotEmpty && tiersMap.containsKey(offer.tierId)) {
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
              'labourPriceMin': tierData['labourPriceMin'] ?? offer.labourPriceMin,
              'labourPriceMax': tierData['labourPriceMax'] ?? offer.labourPriceMax,
              'duration': tierData['duration'] ?? offer.duration,
            };
          }
        } else {
          // Check with offer's own compatibility data
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

        // Only include compatible ACTIVE offers in pricing calculation
        if (isOfferCompatible) {
          double partPrice = effectivePricing?['price'] ?? offer.partPrice;
          double labourPrice = effectivePricing?['labourPrice'] ?? offer.labourPrice;
          double partPriceMin = effectivePricing?['priceMin'] ?? offer.partPriceMin;
          double partPriceMax = effectivePricing?['priceMax'] ?? offer.partPriceMax;
          double labourPriceMin = effectivePricing?['labourPriceMin'] ?? offer.labourPriceMin;
          double labourPriceMax = effectivePricing?['labourPriceMax'] ?? offer.labourPriceMax;
          int duration = effectivePricing?['duration'] ?? offer.duration;

          validOffers++;

          // Aggregate part and labour prices separately
          totalPartPrice += partPrice;
          totalLabourPrice += labourPrice;
          totalPartPriceMin += partPriceMin;
          totalPartPriceMax += partPriceMax;
          totalLabourPriceMin += labourPriceMin;
          totalLabourPriceMax += labourPriceMax;
          totalDuration += duration; // FIX: Properly accumulate duration

          // Check if all offers have fixed pricing
          if (partPrice <= 0 || labourPrice <= 0) {
            hasAllFixedPrices = false;
          }
        }
      }

      // FIX: If no valid offers found, use the package's default duration
      if (validOffers == 0) {
        totalDuration = package.estimatedDuration;
      }

      return {
        'hasFixedPrice': hasAllFixedPrices && validOffers > 0,
        'fixedPrice': hasAllFixedPrices ? (totalPartPrice + totalLabourPrice) : 0.0,
        'totalPartPrice': totalPartPrice,
        'totalLabourPrice': totalLabourPrice,
        'minPartPrice': totalPartPriceMin,
        'maxPartPrice': totalPartPriceMax,
        'minLabourPrice': totalLabourPriceMin,
        'maxLabourPrice': totalLabourPriceMax,
        'duration': totalDuration, // FIX: Use the calculated total duration
        'validOffers': validOffers,
      };
    } catch (e) {
      debugPrint('Error calculating package pricing for ${package.name}: $e');
      return {
        'hasFixedPrice': false,
        'fixedPrice': 0.0,
        'totalPartPrice': 0.0,
        'totalLabourPrice': 0.0,
        'minPartPrice': 0.0,
        'maxPartPrice': 0.0,
        'minLabourPrice': 0.0,
        'maxLabourPrice': 0.0,
        'duration': package.estimatedDuration, // FIX: Fallback to package duration
        'validOffers': 0,
      };
    }
  }

  Widget _buildPackagePriceInfo(models.ServicePackage package) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _calculatePackagePricing(package),
      builder: (context, snapshot) {
        final pricing = snapshot.data ?? {
          'hasFixedPrice': false,
          'fixedPrice': 0.0,
          'totalPartPrice': 0.0,
          'totalLabourPrice': 0.0,
          'minPartPrice': 0.0,
          'maxPartPrice': 0.0,
          'minLabourPrice': 0.0,
          'maxLabourPrice': 0.0,
          'duration': package.estimatedDuration,
        };

        double partPrice = pricing['totalPartPrice'] as double;
        double labourPrice = pricing['totalLabourPrice'] as double;
        double partPriceMin = pricing['minPartPrice'] as double;
        double partPriceMax = pricing['maxPartPrice'] as double;
        double labourPriceMin = pricing['minLabourPrice'] as double;
        double labourPriceMax = pricing['maxLabourPrice'] as double;
        int duration = pricing['duration'] as int;

        // Check if we have any fixed pricing (either parts OR labour, not necessarily both) - SAME AS SERVICES
        bool hasAnyFixedPricing = partPrice > 0 || labourPrice > 0;
        bool hasAnyRangePricing = partPriceMin > 0 || partPriceMax > 0 || labourPriceMin > 0 || labourPriceMax > 0;

        // Calculate totals - SAME AS SERVICES
        double fixedTotal = partPrice + labourPrice;
        double minTotal = partPriceMin + labourPriceMin;
        double maxTotal = partPriceMax + labourPriceMax;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // If both fixed and range pricing exist - FIXED: Show proper range from min to max
            if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warningColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Parts: RM${partPrice.toStringAsFixed(2)}${partPriceMin > 0 || partPriceMax > 0 ? ' (+RM${partPriceMin.toStringAsFixed(2)}-RM${partPriceMax.toStringAsFixed(2)})' : ''} | Labour: RM${labourPrice.toStringAsFixed(2)}${labourPriceMin > 0 || labourPriceMax > 0 ? ' (+RM${labourPriceMin.toStringAsFixed(2)}-RM${labourPriceMax.toStringAsFixed(2)})' : ''}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              )
            // If only fixed pricing exists (at least one component has a price) - SAME AS SERVICES
            else if (hasAnyFixedPricing && !hasAnyRangePricing)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RM${fixedTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.successColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Parts: RM${partPrice.toStringAsFixed(2)} | Labour: RM${labourPrice.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              )
            // If only range pricing exists - SAME AS SERVICES
            else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warningColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Parts: RM${partPriceMin.toStringAsFixed(2)}-${partPriceMax.toStringAsFixed(2)} | Labour: RM${labourPriceMin.toStringAsFixed(2)}-${labourPriceMax.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                )
              // Fallback - no pricing available - SAME AS SERVICES
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price on request',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Parts: RM${partPrice.toStringAsFixed(2)} | Labour: RM${labourPrice.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: AppColors.accentColor),
                const SizedBox(width: 4),
                Text(
                  '${duration} min',
                  style: TextStyle(
                    color: AppColors.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCartBottomSheet() {

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // double totalPrice = _calculateTotalPrice();

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

                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Cart',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (selectedServiceCenter != null)
                              Text(
                                selectedServiceCenter!.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.surfaceColor,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child:
                    (cartItems.isEmpty && cartPackages.isEmpty)
                        ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.shopping_cart_outlined,
                              size: 64,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Your cart is empty',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add services or packages to get started',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      children: [
                        // Service packages
                        ...cartPackages
                            .map(
                              (package) => _buildCartPackageItem(
                            package,
                            setModalState,
                          ),
                        )
                            .toList(),

                        // Individual services
                        ...cartItems
                            .map(
                              (service) => _buildCartServiceItem(
                            service,
                            setModalState,
                          ),
                        )
                            .toList(),
                      ],
                    ),
                  ),

                  if (cartItems.isNotEmpty || cartPackages.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceColor,
                        border: Border(
                          top: BorderSide(color: AppColors.borderColor),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildCartTotalSection(),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.calendar_today_rounded),
                              label: const Text('Make Appointment'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                foregroundColor: AppColors.cardColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              onPressed: _proceedToAppointment,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCartServiceItem(
      ServiceCenterServiceOffer service,
      StateSetter setModalState,
      ) {
    final effectivePricing = this.effectivePricing[service.id];

    double partPrice = effectivePricing?['price'] ?? service.partPrice;
    double labourPrice = effectivePricing?['labourPrice'] ?? service.labourPrice;
    double partPriceMin = effectivePricing?['priceMin'] ?? service.partPriceMin;
    double partPriceMax = effectivePricing?['priceMax'] ?? service.partPriceMax;
    double labourPriceMin = effectivePricing?['labourPriceMin'] ?? service.labourPriceMin;
    double labourPriceMax = effectivePricing?['labourPriceMax'] ?? service.labourPriceMax;

    // Check if we have any fixed pricing (either parts OR labour, not necessarily both)
    bool hasAnyFixedPricing = partPrice > 0 || labourPrice > 0;
    bool hasAnyRangePricing = partPriceMin > 0 || partPriceMax > 0 || labourPriceMin > 0 || labourPriceMax > 0;

    // Calculate totals
    double fixedTotal = partPrice + labourPrice;
    double minTotal = partPriceMin + labourPriceMin;
    double maxTotal = partPriceMax + labourPriceMax;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _getServiceColor(
                    service.serviceName ?? '',
                  ).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getServiceIcon(service.serviceName ?? ''),
                  color: _getServiceColor(service.serviceName ?? ''),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.serviceName ?? 'Unknown Service',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (service.serviceDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.serviceDescription,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Apply the same pricing logic as services and packages
                    if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0)
                      Text(
                        'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.warningColor,
                        ),
                        textAlign: TextAlign.end,
                      )
                    else if (hasAnyFixedPricing && !hasAnyRangePricing)
                      Text(
                        'RM${fixedTotal.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.successColor,
                        ),
                        textAlign: TextAlign.end,
                      )
                    else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0))
                        Text(
                          'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.warningColor,
                          ),
                          textAlign: TextAlign.end,
                        )
                      else
                        Text(
                          'RM0.00',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                          textAlign: TextAlign.end,
                        ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: AppColors.accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Est duration: ${effectivePricing?['duration'] ?? service.duration} min',
                          style: TextStyle(
                            color: AppColors.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      // Update both modal state and main state
                      setState(() {
                        cartItems.removeWhere((item) => item.id == service.id);
                        if (cartItems.isEmpty && cartPackages.isEmpty) {
                          selectedServiceCenterId = null;
                          selectedServiceCenter = null;
                        }
                      });
                      // Force modal to rebuild
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    color: AppColors.errorColor,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.errorColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPackageItem(
      models.ServicePackage package,
      StateSetter setModalState,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: AppColors.accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${package.services.length} services included',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<Map<String, dynamic>>(
                      future: _calculatePackagePricing(package),
                      builder: (context, snapshot) {
                        final pricing = snapshot.data ?? {
                          'totalPartPrice': 0.0,
                          'totalLabourPrice': 0.0,
                          'minPartPrice': 0.0,
                          'maxPartPrice': 0.0,
                          'minLabourPrice': 0.0,
                          'maxLabourPrice': 0.0,
                        };

                        double partPrice = pricing['totalPartPrice'] as double;
                        double labourPrice = pricing['totalLabourPrice'] as double;
                        double partPriceMin = pricing['minPartPrice'] as double;
                        double partPriceMax = pricing['maxPartPrice'] as double;
                        double labourPriceMin = pricing['minLabourPrice'] as double;
                        double labourPriceMax = pricing['maxLabourPrice'] as double;

                        // Apply the EXACT SAME logic as services
                        bool hasAnyFixedPricing = partPrice > 0 || labourPrice > 0;
                        bool hasAnyRangePricing = partPriceMin > 0 || partPriceMax > 0 || labourPriceMin > 0 || labourPriceMax > 0;

                        double fixedTotal = partPrice + labourPrice;
                        double minTotal = partPriceMin + labourPriceMin;
                        double maxTotal = partPriceMax + labourPriceMax;

                        if (hasAnyFixedPricing && hasAnyRangePricing && maxTotal > 0) {
                          return Text(
                            'RM${(fixedTotal + minTotal).toStringAsFixed(2)} - RM${(fixedTotal + maxTotal).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.warningColor,
                            ),
                          );
                        } else if (hasAnyFixedPricing && !hasAnyRangePricing) {
                          return Text(
                            'RM${fixedTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.successColor,
                            ),
                          );
                        } else if (hasAnyRangePricing && (minTotal > 0 || maxTotal > 0)) {
                          return Text(
                            'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.warningColor,
                            ),
                          );
                        } else {
                          return const Text(
                            'Quote on request',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 4,),
                    FutureBuilder<Map<String, dynamic>>(
                      future: _calculatePackagePricing(package),
                      builder: (context, snapshot) {
                        final pricing = snapshot.data ?? {'duration': package.estimatedDuration};
                        int duration = pricing['duration'] as int;

                        return Row(
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: AppColors.accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Est duration: ${duration} min',
                              style: const TextStyle(
                                color: AppColors.accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        cartPackages.removeWhere((item) => item.id == package.id);
                        if (cartItems.isEmpty && cartPackages.isEmpty) {
                          selectedServiceCenterId = null;
                          selectedServiceCenter = null;
                        }
                      });
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    color: AppColors.errorColor,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.errorColor.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartTotalSection() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _calculateTotalPriceWithDetails(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryColor),
          );
        }

        final data = snapshot.data ?? {
          'total': 0.0,
          'minTotal': 0.0,
          'maxTotal': 0.0,
          'hasFixedPricing': false,
          'hasRangePricing': false,
        };

        double total = data['total'] ?? 0.0;
        double minTotal = data['minTotal'] ?? 0.0;
        double maxTotal = data['maxTotal'] ?? 0.0;
        bool hasRangePricing = data['hasRangePricing'] ?? false;

        bool cartHasItems = cartItems.isNotEmpty || cartPackages.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (cartHasItems && total > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Show range if ANY item has range pricing
                      if (hasRangePricing && maxTotal > minTotal)
                        Text(
                          'RM${minTotal.toStringAsFixed(2)} - RM${maxTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warningColor,
                          ),
                        )
                      else
                        Text(
                          'RM${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      if (hasRangePricing)
                        Text(
                          'Estimated total',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  )
                else if (cartHasItems)
                  Text(
                    'RM0.00',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                    ),
                  )
                else
                  Text(
                    'RM0.00',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
            // Show range information if we have range pricing
            if (cartHasItems && hasRangePricing && maxTotal > minTotal)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.warningColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Final amount may vary based on actual parts and labour required.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.warningColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

}