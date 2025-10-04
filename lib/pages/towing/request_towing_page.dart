import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyTowingPage extends StatefulWidget {
  final String userId;
  final String userName;

  const EmergencyTowingPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<EmergencyTowingPage> createState() => _EmergencyTowingPageState();
}

class _EmergencyTowingPageState extends State<EmergencyTowingPage> {
  // App Colors
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  // Current page state
  int _currentStep = 0;
  String? _selectedTowingType;
  String? _selectedServiceCenter;
  Map<String, dynamic>? _selectedServiceCenterData;
  Position? _currentPosition;
  String? _currentLocation;
  // dynamic _distance;
  double? _estimatedCost;
  double? _distanceInKm;

  // Form data
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Vehicle data
  String? _vehiclePlate;
  String? _vehicleMake;
  String? _vehicleModel;
  String? _vehicleYear;
  String? _vehicleSizeClass;
  List<Map<String, dynamic>> _userVehicles = [];
  Map<String, dynamic>? _selectedVehicle;
  String? _selectedVehicleId;

  // Available service centers with towing
  List<Map<String, dynamic>> _availableServiceCenters = [];
  bool _loadingServiceCenters = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _ensureLocationAvailable();
    await _getCurrentLocation();
    await _loadVehicleData();
    await _loadTowingServiceTypes();
    await _loadAvailableServiceCenters();
  }

  Future<void> _ensureLocationAvailable() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Location service is not enabled, show a dialog or message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location services are disabled. Please enable location services for accurate distance calculation.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Location permissions are denied. Distance calculation may not be accurate.',
                ),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permissions are permanently denied. Please enable them in app settings.',
              ),
            ),
          );
        }
        return;
      }

      // If we don't have current position, try to get it again
      if (_currentPosition == null) {
        await _getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error ensuring location available: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied');
        return;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      debugPrint(
        'Current position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String city = place.locality?.isNotEmpty == true ? place.locality! : '';
        String state = place.administrativeArea ?? '';
        setState(() {
          _currentLocation = city.isNotEmpty ? '$city, $state' : state;
        });
        debugPrint('Current location: $_currentLocation');
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _loadVehicleData() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      if (doc.exists && doc.data()!['vehicles'] != null) {
        final vehicles = List<Map<String, dynamic>>.from(
          doc.data()!['vehicles'],
        );
        final approvedVehicles =
            vehicles.where((v) => (v['status'] ?? '') == 'approved').toList();

        setState(() {
          _userVehicles = approvedVehicles;
          // Auto-select first vehicle if available
          if (_userVehicles.isNotEmpty) {
            _selectedVehicle = _userVehicles.first;
            _selectedVehicleId =
                _selectedVehicle!['id']?.toString() ??
                _userVehicles.indexOf(_selectedVehicle!).toString();
            _vehiclePlate = _selectedVehicle!['plateNumber'];
            _vehicleMake = _selectedVehicle!['make'];
            _vehicleModel = _selectedVehicle!['model'];
            _vehicleYear = _selectedVehicle!['year']?.toString();
            _vehicleSizeClass = _selectedVehicle!['sizeClass'] ?? 'Medium';
          }
        });
      }

      // Pre-fill contact info
      if (doc.exists) {
        final data = doc.data()!;
        _contactController.text = data['phone'] ?? '';
        _emailController.text = data['email'] ?? '';
      }
    } catch (e) {
      debugPrint('Vehicle data error: $e');
    }
  }

  Future<void> _loadAvailableServiceCenters() async {
    setState(() => _loadingServiceCenters = true);

    try {
      final serviceCentersQuery =
          await FirebaseFirestore.instance.collection('service_centers').get();

      List<Map<String, dynamic>> availableCenters = [];

      for (var centerDoc in serviceCentersQuery.docs) {
        try {
          final centerData = centerDoc.data();
          final centerId = centerDoc.id;

          final towingDoc =
              await FirebaseFirestore.instance
                  .collection('service_center_towing_services_offer')
                  .doc(centerId)
                  .get();

          if (towingDoc.exists) {
            final towingData = towingDoc.data()!;

            if (towingData.containsKey('towing')) {
              final towingInfo = towingData['towing'] as Map<String, dynamic>?;

              // Check if service center offers towing AND the specific selected service type
              if (towingInfo != null &&
                  towingInfo['offers'] == true &&
                  _selectedTowingType != null) {
                final offeredTypes = List<String>.from(
                  towingInfo['types'] ?? [],
                );

                // Check if this service center offers the selected towing type
                bool offersSelectedType = offeredTypes.any(
                  (type) =>
                      type.toLowerCase() == _selectedTowingType!.toLowerCase(),
                );

                if (offersSelectedType) {
                  // Calculate distance if we have current position
                  double? distance;
                  if (_currentPosition != null) {
                    // CORRECTED: Get coordinates from serviceCenterInfo at root level
                    final serviceCenterInfo =
                        centerData['serviceCenterInfo']
                            as Map<String, dynamic>?;
                    if (serviceCenterInfo != null) {
                      final centerLat = serviceCenterInfo['latitude'];
                      final centerLng = serviceCenterInfo['longitude'];

                      if (centerLat != null && centerLng != null) {
                        distance =
                            Geolocator.distanceBetween(
                              _currentPosition!.latitude,
                              _currentPosition!.longitude,
                              centerLat.toDouble(),
                              centerLng.toDouble(),
                            ) /
                            1000; // Convert to kilometers

                        // Round to 1 decimal place
                        distance = double.parse(distance.toStringAsFixed(1));
                        debugPrint(
                          'Distance calculated: $distance km from user to ${serviceCenterInfo['name']}',
                        );
                      } else {
                        debugPrint(
                          'Service center coordinates missing for ${serviceCenterInfo['name']}',
                        );
                      }
                    } else {
                      debugPrint(
                        'Service center info missing for center $centerId',
                      );
                    }
                  } else {
                    debugPrint(
                      'Current position is null, cannot calculate distance',
                    );
                  }

                  // Get service fee for the selected towing type
                  double? serviceFee;
                  final serviceFees = towingInfo['serviceFees'] as List? ?? [];
                  final matchingFee = serviceFees.firstWhere(
                    (fee) => fee['type'] == _selectedTowingType,
                    orElse: () => {},
                  );
                  if (matchingFee.isNotEmpty && matchingFee['fee'] != null) {
                    serviceFee = _safeParseDouble(matchingFee['fee']);
                  }

                  // Get service center info
                  final serviceCenterInfo =
                      centerData['serviceCenterInfo']
                          as Map<String, dynamic>? ??
                      {};

                  availableCenters.add({
                    'id': centerId,
                    'name': serviceCenterInfo['name'] ?? 'Unknown',
                    'address': _formatAddress(serviceCenterInfo['address']),
                    'phone': serviceCenterInfo['serviceCenterPhoneNo'] ?? 'N/A',
                    'distance': distance,
                    'towingData': towingInfo,
                    'serviceFee': serviceFee,
                    'coordinates': {
                      'latitude': serviceCenterInfo['latitude'],
                      'longitude': serviceCenterInfo['longitude'],
                    },
                  });
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Error processing center ${centerDoc.id}: $e');
          continue;
        }
      }

      // Sort by distance if available
      availableCenters.sort((a, b) {
        final distA = a['distance'] ?? double.infinity;
        final distB = b['distance'] ?? double.infinity;
        return distA.compareTo(distB);
      });

      setState(() {
        _availableServiceCenters = availableCenters;
        _loadingServiceCenters = false;
      });
    } catch (e) {
      debugPrint('Error loading service centers: $e');
      setState(() => _loadingServiceCenters = false);
    }
  }

  String _formatAddress(Map<String, dynamic>? address) {
    if (address == null) return 'Unknown location';

    final parts =
        [
          address['addressLine1'],
          address['addressLine2'],
          address['city'],
          address['state'],
          address['postalCode'],
        ].where((part) => part != null && part.toString().isNotEmpty).toList();

    return parts.join(', ');
  }

  List<Map<String, dynamic>> _availableTowingTypes = [];
  bool _loadingTowingTypes = false;

  // Replace the static _towingTypes with dynamic loading
  Future<void> _loadTowingServiceTypes() async {
    setState(() => _loadingTowingTypes = true);

    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('towing_services')
              .where('active', isEqualTo: true)
              .get();

      _availableTowingTypes =
          querySnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'title': data['name'],
              'subtitle': data['description'],
              'icon': _mapServiceToIcon(data['name']),
              'color': _mapServiceToColor(data['name']),
            };
          }).toList();
    } catch (e) {
      debugPrint('Error loading towing types: $e');
    } finally {
      setState(() => _loadingTowingTypes = false);
    }
  }

  IconData _mapServiceToIcon(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'vehicle brakedown':
      case 'vehicle breakdown':
        return Icons.car_crash;
      case 'flat tire / tire burst':
        return Icons.tire_repair;
      case 'accident / collision':
      case 'accident recovery':
        return Icons.warning;
      case 'out of fuel':
        return Icons.local_gas_station;
      case 'battery dead':
        return Icons.battery_alert;
      case 'locked out / lost key':
        return Icons.key_off;
      case 'engine overheating / engine failure':
        return Icons.local_fire_department;
      default:
        return Icons.build;
    }
  }

  Color _mapServiceToColor(String serviceName) {
    switch (serviceName.toLowerCase()) {
      case 'vehicle brakedown':
      case 'vehicle breakdown':
        return Colors.red;
      case 'flat tire / tire burst':
        return Colors.orange;
      case 'accident / collision':
      case 'accident recovery':
        return Colors.amber;
      case 'out of fuel':
        return Colors.green;
      case 'battery dead':
        return Colors.blue;
      case 'locked out / lost key':
        return Colors.purple;
      case 'engine overheating / engine failure':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  void _calculateEstimatedCost() {
    try {
      if (_selectedServiceCenterData == null ||
          _selectedTowingType == null ||
          _selectedVehicle == null) {
        setState(() {
          _estimatedCost = 0.0;
        });
        return;
      }

      final towingData = _selectedServiceCenterData!['towingData'];
      if (towingData == null) {
        setState(() {
          _estimatedCost = 0.0;
        });
        return;
      }

      double baseFee = 0.0;
      double perKmRate = 0.0;

      // 1. Get base fee from serviceFees based on towing type
      final serviceFees = towingData['serviceFees'] as List? ?? [];
      final matchingService = serviceFees.firstWhere(
        (service) => service['type'] == _selectedTowingType,
        orElse: () => {},
      );

      if (matchingService.isNotEmpty && matchingService['fee'] != null) {
        baseFee = _safeParseDouble(matchingService['fee']);
      }

      // 2. Get perKmRate from sizePricing based on vehicle size class
      final sizePricing = towingData['sizePricing'] as List? ?? [];
      final vehicleSizeClass = _selectedVehicle!['sizeClass'] ?? 'Medium';
      final matchingSize = sizePricing.firstWhere(
        (pricing) => pricing['sizeClass'] == vehicleSizeClass,
        orElse: () => {},
      );

      if (matchingSize.isNotEmpty && matchingSize['perKmRate'] != null) {
        perKmRate = _safeParseDouble(matchingSize['perKmRate']);
      }

      // 3. Use actual distance from service center data, fallback to 10km if null
      double distanceInKm = _selectedServiceCenterData!['distance'] ?? 10.0;

      // Update the _distanceInKm variable for use in other parts of the app
      _distanceInKm = distanceInKm;

      double distanceCost = distanceInKm * perKmRate;
      double totalCost = baseFee + distanceCost;

      // 4. Apply luxury surcharge if applicable
      final luxurySurcharge = towingData['luxurySurcharge'] as List? ?? [];
      final vehicleMake = _selectedVehicle!['make'];
      final luxuryMake = luxurySurcharge.firstWhere(
        (make) => make['make'] == vehicleMake,
        orElse: () => {},
      );

      if (luxuryMake.isNotEmpty && luxuryMake['surcharge'] != null) {
        double surcharge = _safeParseDouble(luxuryMake['surcharge']);
        totalCost += surcharge;
      }

      setState(() {
        _estimatedCost = totalCost;
      });
    } catch (e) {
      debugPrint('Error calculating estimated cost: $e');
      setState(() {
        _estimatedCost = 0.0;
      });
    }
  }

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value == "N/A") return 0.0;

    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    } else if (value is int) {
      return value.toDouble();
    } else if (value is double) {
      return value;
    }
    return 0.0;
  }

  Future<void> _submitTowingRequest() async {
    if (_selectedTowingType == null || _selectedServiceCenter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields')),
      );
      return;
    }

    if (_contactController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a contact number')),
      );
      return;
    }

    try {
      // Create towing request
      final requestRef = await FirebaseFirestore.instance
          .collection('towing_requests')
          .add({
            'userId': widget.userId,
            'serviceCenterId': _selectedServiceCenter,
            'serviceCenterName': _selectedServiceCenterData!['name'],
            'towingType': _selectedTowingType,
            'description': _descriptionController.text.trim(),
            'contactNumber': _contactController.text.trim(),
            'email': _emailController.text.trim(),
            'vehicleInfo': {
              'plateNumber': _vehiclePlate,
              'make': _vehicleMake,
              'model': _vehicleModel,
              'year': _vehicleYear,
              'sizeClass': _vehicleSizeClass,
            },
            'location':
                _currentPosition != null
                    ? {
                      'latitude': _currentPosition!.latitude,
                      'longitude': _currentPosition!.longitude,
                      'address': _currentLocation,
                    }
                    : null,
            'estimatedCost': _estimatedCost,
            'distance': _selectedServiceCenterData!['distance'],
            'status': 'pending', // pending -> assigned -> ongoing -> completed
            'driverId': null, // Will be assigned later
            'driverInfo': null, // Will be filled when driver is assigned
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        // Navigate to request tracking page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => TowingRequestTrackingPage(
                  requestId: requestRef.id,
                  userId: widget.userId,
                ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit request. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _makeEmergencyCall() async {
    const url = 'tel:999'; // Malaysian emergency number
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Emergency Towing',
          style: TextStyle(
            color: secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: secondaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.phone, color: Colors.red, size: 20),
            ),
            onPressed: _makeEmergencyCall,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(child: _buildCurrentStep()),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: cardColor,
      child: Row(
        children: [
          _buildStepIndicator(0, 'Vehicle', _currentStep >= 0),
          Expanded(child: _buildConnector(_currentStep >= 1)),
          _buildStepIndicator(1, 'Service', _currentStep >= 1),
          Expanded(child: _buildConnector(_currentStep >= 2)),
          _buildStepIndicator(2, 'Center', _currentStep >= 2),
          Expanded(child: _buildConnector(_currentStep >= 3)),
          _buildStepIndicator(3, 'Details', _currentStep >= 3),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? primaryColor : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child:
                isActive
                    ? const Icon(Icons.check, color: Colors.white, size: 18)
                    : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive ? primaryColor : Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildConnector(bool isActive) {
    return Container(
      height: 2,
      color: isActive ? primaryColor : Colors.grey.shade300,
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildVehicleSelection();
      case 1:
        return _buildTowingTypeSelection();
      case 2:
        return _buildServiceCenterSelection();
      case 3:
        return _buildRequestDetails();
      default:
        return _buildVehicleSelection();
    }
  }

  Widget _buildVehicleSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Vehicle for Towing',
            style: TextStyle(
              color: secondaryColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose which vehicle needs towing assistance',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 24),

          if (_userVehicles.isEmpty)
            _buildEmptyVehicleState()
          else
            ..._userVehicles.map((vehicle) {
              final vehicleId =
                  vehicle['id']?.toString() ??
                  _userVehicles.indexOf(vehicle).toString();
              final isSelected = _selectedVehicleId == vehicleId;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  elevation: isSelected ? 4 : 1,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _selectedVehicleId = vehicleId;
                        _selectedVehicle = vehicle;
                        _vehiclePlate = vehicle['plateNumber'];
                        _vehicleMake = vehicle['make'];
                        _vehicleModel = vehicle['model'];
                        _vehicleYear = vehicle['year']?.toString();
                        _vehicleSizeClass = vehicle['sizeClass'] ?? 'Medium';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isSelected ? primaryColor : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${vehicle['make']} ${vehicle['model']}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        isSelected
                                            ? primaryColor
                                            : secondaryColor,
                                  ),
                                ),
                                Text(
                                  '${vehicle['plateNumber']} • ${vehicle['year']}',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                if (vehicle['sizeClass'] != null)
                                  Text(
                                    'Size: ${vehicle['sizeClass']}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? primaryColor
                                      : Colors.transparent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected
                                        ? primaryColor
                                        : Colors.grey.shade400,
                              ),
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
            }).toList(),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed:
                  _selectedVehicle != null
                      ? () => setState(() => _currentStep = 1)
                      : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Continue to Service Type',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyVehicleState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.directions_car_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Vehicles Found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Please add a vehicle to your profile first',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTowingTypeSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What happened to your vehicle?',
            style: TextStyle(
              color: secondaryColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the type of assistance you need',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 24),

          // Emergency banner
          // Container(
          //   padding: const EdgeInsets.all(16),
          //   decoration: BoxDecoration(
          //     color: Colors.red.shade50,
          //     borderRadius: BorderRadius.circular(12),
          //     border: Border.all(color: Colors.red.shade200),
          //   ),
          //   child: Row(
          //     children: [
          //       Icon(Icons.emergency, color: Colors.red.shade600, size: 24),
          //       const SizedBox(width: 12),
          //       Expanded(
          //         child: Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: [
          //             Text(
          //               'Emergency Assistance',
          //               style: TextStyle(
          //                 color: Colors.red.shade800,
          //                 fontWeight: FontWeight.w600,
          //                 fontSize: 14,
          //               ),
          //             ),
          //             const SizedBox(height: 2),
          //             Text(
          //               'For immediate help, call emergency services',
          //               style: TextStyle(
          //                 color: Colors.red.shade700,
          //                 fontSize: 12,
          //               ),
          //             ),
          //           ],
          //         ),
          //       ),
          //       TextButton(
          //         onPressed: _makeEmergencyCall,
          //         child: Text(
          //           'Call',
          //           style: TextStyle(color: Colors.red.shade700),
          //         ),
          //       ),
          //     ],
          //   ),
          // ),
          //
          // const SizedBox(height: 24),

          // Loading state for towing types
          if (_loadingTowingTypes)
            const Center(child: CircularProgressIndicator(color: primaryColor)),

          // Towing service types grid
          if (!_loadingTowingTypes)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
              ),
              itemCount: _availableTowingTypes.length,
              itemBuilder: (context, index) {
                final towingType = _availableTowingTypes[index];
                final isSelected = _selectedTowingType == towingType['title'];

                return Material(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  elevation: isSelected ? 8 : 3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await _ensureLocationAvailable(); // Ensure location is available
                      setState(() {
                        _selectedTowingType = towingType['title'];
                      });
                      // Reload service centers that offer this specific service
                      await _loadAvailableServiceCenters();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border:
                            isSelected
                                ? Border.all(color: primaryColor, width: 2)
                                : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: (towingType['color'] as Color).withOpacity(
                                0.1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              towingType['icon'],
                              color: towingType['color'],
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            towingType['title'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isSelected ? primaryColor : secondaryColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            towingType['subtitle'],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 32),

          // Next button
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      _selectedTowingType != null
                          ? () => setState(() => _currentStep = 2)
                          : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCenterSelection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Service Centers for $_selectedTowingType',
                style: const TextStyle(
                  color: secondaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a service center that offers $_selectedTowingType',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              // Add current location display
              if (_currentLocation != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: primaryColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Your location: $_currentLocation',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child:
              _loadingServiceCenters
                  ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        SizedBox(height: 16),
                        Text('Finding service centers...'),
                      ],
                    ),
                  )
                  : _availableServiceCenters.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No service centers found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No service centers offer $_selectedTowingType in your area',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => setState(() => _currentStep = 1),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Choose Different Service'),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _availableServiceCenters.length,
                    itemBuilder: (context, index) {
                      final center = _availableServiceCenters[index];
                      final isSelected = _selectedServiceCenter == center['id'];
                      final towingData = center['towingData'];
                      final distance = center['distance'];
                      final coverageKm = towingData['coverageKm'] ?? 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          borderRadius: BorderRadius.circular(16),
                          elevation: isSelected ? 8 : 3,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                _selectedServiceCenter = center['id'];
                                _selectedServiceCenterData = center;
                                _distanceInKm = center['distance'] ?? 10.0;
                              });
                              _calculateEstimatedCost();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border:
                                    isSelected
                                        ? Border.all(
                                          color: primaryColor,
                                          width: 2,
                                        )
                                        : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Service Center Name and Distance
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          center['name'],
                                          style: TextStyle(
                                            color:
                                                isSelected
                                                    ? primaryColor
                                                    : secondaryColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (distance != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getDistanceColor(
                                              distance,
                                              coverageKm,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                size: 12,
                                                color: _getDistanceTextColor(
                                                  distance,
                                                  coverageKm,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${distance.toStringAsFixed(1)} km',
                                                style: TextStyle(
                                                  color: _getDistanceTextColor(
                                                    distance,
                                                    coverageKm,
                                                  ),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Service Center Address
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_on,
                                        size: 16,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          center['address'],
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Service Details Row
                                  Row(
                                    children: [
                                      // Response Time
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '${towingData['responseTimeMins'] ?? 'N/A'} min response',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Coverage Area
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.place,
                                              size: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '${coverageKm} km coverage',
                                                style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Distance Status Indicator
                                  if (distance != null) ...[
                                    const SizedBox(height: 8),
                                    _buildDistanceStatus(distance, coverageKm),
                                  ],

                                  // Service Fee
                                  if (center['serviceFee'] != null) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.attach_money,
                                          size: 16,
                                          color: Colors.green.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Service Fee: RM ${center['serviceFee']!.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  // Estimated Cost (when selected)
                                  if (isSelected && _estimatedCost != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calculate,
                                            color: primaryColor,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Total Estimated: ',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'RM ${_estimatedCost!.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: primaryColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 8),

                                  // Call Button and Distance Text
                                  Row(
                                    children: [
                                      // Distance from you text
                                      if (distance != null) ...[
                                        Expanded(
                                          child: Text(
                                            '${distance.toStringAsFixed(1)} km from your location',
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (center['phone'] != null)
                                        TextButton.icon(
                                          onPressed:
                                              () => _makeCall(center['phone']),
                                          icon: const Icon(
                                            Icons.phone,
                                            size: 16,
                                          ),
                                          label: const Text('Call'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: primaryColor,
                                            textStyle: const TextStyle(
                                              fontSize: 12,
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
                    },
                  ),
        ),

        // Navigation buttons
        Container(
          padding: const EdgeInsets.all(20),
          color: cardColor,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 1),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      _selectedServiceCenter != null
                          ? () => setState(() => _currentStep = 3)
                          : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDistanceStatus(double distance, int coverageKm) {
    bool isWithinCoverage = distance <= coverageKm;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isWithinCoverage ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              isWithinCoverage ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isWithinCoverage ? Icons.check_circle : Icons.info,
            size: 12,
            color:
                isWithinCoverage
                    ? Colors.green.shade600
                    : Colors.orange.shade600,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              isWithinCoverage
                  ? 'Within service coverage area'
                  : 'Outside coverage area - extra charges may apply',
              style: TextStyle(
                color:
                    isWithinCoverage
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDistanceColor(double distance, int coverageKm) {
    if (distance <= coverageKm * 0.5) {
      return Colors.green.shade100; // Very close
    } else if (distance <= coverageKm) {
      return Colors.blue.shade100; // Within coverage
    } else if (distance <= coverageKm * 1.5) {
      return Colors.orange.shade100; // Slightly outside
    } else {
      return Colors.red.shade100; // Far outside
    }
  }

  Color _getDistanceTextColor(double distance, int coverageKm) {
    if (distance <= coverageKm * 0.5) {
      return Colors.green.shade700;
    } else if (distance <= coverageKm) {
      return Colors.blue.shade700;
    } else if (distance <= coverageKm * 1.5) {
      return Colors.orange.shade700;
    } else {
      return Colors.red.shade700;
    }
  }

  Widget _buildRequestDetails() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          color: cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Details',
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Provide additional information for your request',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle summary
                Container(
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
                      const Text(
                        'Vehicle Information',
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_vehiclePlate != null)
                        _buildDetailRow('Plate Number', _vehiclePlate!),
                      if (_vehicleMake != null && _vehicleModel != null)
                        _buildDetailRow(
                          'Vehicle',
                          '$_vehicleMake $_vehicleModel',
                        ),
                      if (_vehicleYear != null)
                        _buildDetailRow('Year', _vehicleYear!),
                      if (_vehicleSizeClass != null)
                        _buildDetailRow('Size Class', _vehicleSizeClass!),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Service summary
                Container(
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
                      const Text(
                        'Service Details',
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow('Service Type', _selectedTowingType!),
                      _buildDetailRow(
                        'Service Center',
                        _selectedServiceCenterData!['name'],
                      ),
                      if (_currentLocation != null)
                        _buildDetailRow(
                          'Your Current Location',
                          _currentLocation!,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Pricing Summary
                if (_estimatedCost != null &&
                    _selectedServiceCenterData != null)
                  Container(
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
                        const Text(
                          'Pricing Summary',
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildPricingBreakdown(),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primaryColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Estimated Cost:',
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'RM ${_estimatedCost!.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: primaryColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Contact information
                const Text(
                  'Contact Information',
                  style: TextStyle(
                    color: secondaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _contactController,
                  decoration: InputDecoration(
                    labelText: 'Contact Number *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cardColor,
                    prefixIcon: const Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),

                const SizedBox(height: 16),

                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cardColor,
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 20),

                // Description
                const Text(
                  'Additional Details',
                  style: TextStyle(
                    color: secondaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Describe the issue (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: cardColor,
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: 24),

                // Terms and conditions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Important Notice',
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Final cost may vary based on actual distance and services required\n'
                        '• Driver will contact you once assigned\n'
                        '• Keep your phone accessible for communication\n'
                        '• Payment will be collected upon service completion',
                        style: TextStyle(
                          color: Colors.amber.shade700,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Submit button
        Container(
          padding: const EdgeInsets.all(20),
          color: cardColor,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _currentStep = 2),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryColor,
                        side: const BorderSide(color: primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitTowingRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Request Tow',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
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
                color: secondaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingBreakdown() {
    if (_selectedServiceCenterData == null || _selectedVehicle == null) {
      return const Text('Calculating pricing...');
    }

    final towingData = _selectedServiceCenterData!['towingData'];
    if (towingData == null) {
      return const Text('Pricing information not available');
    }

    double baseFee = 0.0;
    double perKmRate = 0.0;
    double distanceInKm = _distanceInKm ?? 10.0;
    double luxurySurcharge = 0.0;

    // Get base fee from serviceFees
    final serviceFees = towingData['serviceFees'] as List? ?? [];
    final matchingService = serviceFees.firstWhere(
      (service) => service['type'] == _selectedTowingType,
      orElse: () => {},
    );

    if (matchingService.isNotEmpty && matchingService['fee'] != null) {
      baseFee = _safeParseDouble(matchingService['fee']);
    }

    // Get perKmRate from sizePricing
    final sizePricing = towingData['sizePricing'] as List? ?? [];
    final vehicleSizeClass = _selectedVehicle!['sizeClass'] ?? 'Medium';
    final matchingSize = sizePricing.firstWhere(
      (pricing) => pricing['sizeClass'] == vehicleSizeClass,
      orElse: () => {},
    );

    if (matchingSize.isNotEmpty && matchingSize['perKmRate'] != null) {
      perKmRate = _safeParseDouble(matchingSize['perKmRate']);
    }

    // Calculate luxury surcharge
    final luxurySurcharges = towingData['luxurySurcharge'] as List? ?? [];
    final vehicleMake = _selectedVehicle!['make'];
    final luxuryMake = luxurySurcharges.firstWhere(
      (make) => make['make'] == vehicleMake,
      orElse: () => {},
    );

    if (luxuryMake.isNotEmpty && luxuryMake['surcharge'] != null) {
      luxurySurcharge = _safeParseDouble(luxuryMake['surcharge']);
    }

    double distanceCost = distanceInKm * perKmRate;
    double subtotal = baseFee + distanceCost;
    double total = subtotal + luxurySurcharge;

    return Column(
      children: [
        // Base Service Fee
        _buildPricingRow('Base Service Fee', baseFee, showPlus: false),

        // Distance Cost
        if (perKmRate > 0)
          Column(
            children: [
              const SizedBox(height: 8),
              _buildPricingRow(
                'Distance Cost',
                distanceCost,
                description:
                    '${distanceInKm.toStringAsFixed(1)} km × RM ${perKmRate.toStringAsFixed(2)}/km',
              ),
            ],
          ),

        // Luxury Vehicle Surcharge
        if (luxurySurcharge > 0)
          Column(
            children: [
              const SizedBox(height: 8),
              _buildPricingRow(
                'Luxury Vehicle Surcharge',
                luxurySurcharge,
                description:
                    '${_selectedVehicle!['make']} ${_selectedVehicle!['model']}',
              ),
            ],
          ),

        // Subtotal (only show if there are multiple items)
        if (perKmRate > 0 || luxurySurcharge > 0)
          Column(
            children: [
              const SizedBox(height: 8),
              const Divider(height: 20),
              _buildPricingRow('Subtotal', subtotal, isSubtotal: true),
            ],
          ),
      ],
    );
  }

  // Helper method for pricing rows
  Widget _buildPricingRow(
    String label,
    double amount, {
    String? description,
    bool showPlus = true,
    bool isSubtotal = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSubtotal ? secondaryColor : Colors.grey.shade700,
                  fontSize: isSubtotal ? 14 : 13,
                  fontWeight: isSubtotal ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (description != null && description.isNotEmpty)
                Text(
                  description,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 1,
          child: Text(
            '${showPlus && amount > 0 ? '+' : ''}RM ${amount.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: isSubtotal ? primaryColor : Colors.grey.shade700,
              fontSize: isSubtotal ? 14 : 13,
              fontWeight: isSubtotal ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

// Towing Request Tracking Page
class TowingRequestTrackingPage extends StatefulWidget {
  final String requestId;
  final String userId;

  const TowingRequestTrackingPage({
    super.key,
    required this.requestId,
    required this.userId,
  });

  @override
  State<TowingRequestTrackingPage> createState() =>
      _TowingRequestTrackingPageState();
}

class _TowingRequestTrackingPageState extends State<TowingRequestTrackingPage> {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  Map<String, dynamic>? _requestData;
  Map<String, dynamic>? _driverData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRequestData();
    _listenToRequestUpdates();
  }

  Future<void> _loadRequestData() async {
    try {
      final requestDoc =
          await FirebaseFirestore.instance
              .collection('towing_requests')
              .doc(widget.requestId)
              .get();

      if (requestDoc.exists) {
        setState(() {
          _requestData = requestDoc.data()!;
        });

        // Load driver data if assigned
        if (_requestData!['driverId'] != null) {
          await _loadDriverData(_requestData!['driverId']);
        }
      }
    } catch (e) {
      debugPrint('Error loading request data: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadDriverData(String driverId) async {
    try {
      final driverDoc =
          await FirebaseFirestore.instance
              .collection('drivers')
              .doc(driverId)
              .get();

      if (driverDoc.exists) {
        setState(() {
          _driverData = driverDoc.data()!;
        });
      }
    } catch (e) {
      debugPrint('Error loading driver data: $e');
    }
  }

  void _listenToRequestUpdates() {
    FirebaseFirestore.instance
        .collection('towing_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            setState(() {
              _requestData = snapshot.data()!;
            });

            // Load driver data if newly assigned
            if (_requestData!['driverId'] != null && _driverData == null) {
              _loadDriverData(_requestData!['driverId']);
            }
          }
        });
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Looking for available driver...';
      case 'assigned':
        return 'Driver assigned and on the way';
      case 'ongoing':
        return 'Driver has arrived at your location';
      case 'completed':
        return 'Towing service completed';
      case 'cancelled':
        return 'Request cancelled';
      default:
        return 'Status unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'ongoing':
        return primaryColor;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Towing Request Status',
          style: TextStyle(
            color: secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: secondaryColor),
          onPressed:
              () => Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _getStatusColor(_requestData!['status']),
                    _getStatusColor(_requestData!['status']).withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(
                      _requestData!['status'],
                    ).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    _requestData!['status'] == 'completed'
                        ? Icons.check_circle
                        : Icons.local_shipping,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _getStatusMessage(_requestData!['status']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Request ID: ${widget.requestId.substring(0, 8).toUpperCase()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Driver Information (if assigned)
            if (_driverData != null) ...[
              Container(
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
                    const Text(
                      'Driver Information',
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Icon(
                            Icons.person,
                            color: primaryColor,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _driverData!['name'],
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_driverData!['make']} ${_driverData!['model']}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                _driverData!['carPlate'],
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _makeCall(_driverData!['phoneNo']),
                          icon: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: const Icon(
                              Icons.phone,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
            ],

            // Request Details
            Container(
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
                  const Text(
                    'Request Details',
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('Service Type', _requestData!['towingType']),
                  _buildDetailRow(
                    'Service Center',
                    _requestData!['serviceCenterName'],
                  ),
                  if (_requestData!['estimatedCost'] != null)
                    _buildDetailRow(
                      'Estimated Cost',
                      'RM ${_requestData!['estimatedCost'].toStringAsFixed(2)}',
                    ),
                  if (_requestData!['location']?['address'] != null)
                    _buildDetailRow(
                      'Location',
                      _requestData!['location']['address'],
                    ),
                  if (_requestData!['description']?.isNotEmpty == true)
                    _buildDetailRow(
                      'Description',
                      _requestData!['description'],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Action buttons based on status
            if (_requestData!['status'] == 'pending') ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => _cancelRequest(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel Request'),
                ),
              ),
            ],

            if (_requestData!['status'] == 'completed') ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _showRatingDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Rate Service'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                color: secondaryColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelRequest() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cancel Request'),
            content: const Text(
              'Are you sure you want to cancel this towing request?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await FirebaseFirestore.instance
                        .collection('towing_requests')
                        .doc(widget.requestId)
                        .update({
                          'status': 'cancelled',
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                    Navigator.pop(context);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to cancel request')),
                    );
                  }
                },
                child: const Text('Yes, Cancel'),
              ),
            ],
          ),
    );
  }

  void _showRatingDialog() {
    // Implement rating dialog
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Rate Your Experience'),
            content: const Text('Rating feature coming soon!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }
}
