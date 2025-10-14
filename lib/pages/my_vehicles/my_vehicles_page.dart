import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:automate_application/pages/my_vehicles/edit_vehicle_page.dart';
import 'package:automate_application/pages/my_vehicles/view_vehicle_details_page.dart';

class MyVehiclesPage extends StatefulWidget {
  final String userId;
  final String userName;

  const MyVehiclesPage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<MyVehiclesPage> createState() => _MyVehiclesPageState();
}

class _MyVehiclesPageState extends State<MyVehiclesPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isLoading = true;
  List<Map<String, dynamic>> _vehicles = [];
  Map<String, dynamic> _userInfo = {};
  String? _error;

  // App Colors
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadUser();
    _loadVehicles();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  Future<void> _loadUser() async {
    final userDoc =
        await FirebaseFirestore.instance
            .collection('car_owners')
            .doc(widget.userId)
            .get();

    if (userDoc.exists) {
      final userData = userDoc.data()!;
      setState(() {
        _userInfo = {
          'name': userData['name'],
          'email': userData['email'] ?? '',
          'phone': userData['phone'] ?? '',
        };
      });
    }
  }

  Future<void> _loadVehicles() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      if (!doc.exists) {
        setState(() {
          _error = 'User data not found';
          _isLoading = false;
        });
        return;
      }

      final data = doc.data()!;
      final vehiclesData = data['vehicles'] as List<dynamic>? ?? [];

      List<Map<String, dynamic>> vehicles = [];
      for (var vehicle in vehiclesData) {
        if (vehicle is Map<String, dynamic>) {
          vehicles.add(vehicle);
        }
      }

      setState(() {
        _vehicles = vehicles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load vehicles: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddVehicleDialog(),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Vehicle',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child:
                _isLoading
                    ? _buildLoadingState()
                    : _error != null
                    ? _buildErrorState()
                    : _vehicles.isEmpty
                    ? _buildEmptyState()
                    : _buildVehiclesList(),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: cardColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          child: const Icon(
            Icons.arrow_back_ios_new,
            color: secondaryColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'My Vehicles',
        style: TextStyle(
          color: secondaryColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(Icons.refresh, color: secondaryColor, size: 20),
          ),
          onPressed: _loadVehicles,
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primaryColor),
          SizedBox(height: 16),
          Text(
            'Loading your vehicles...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadVehicles,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.directions_car_outlined,
                size: 64,
                color: primaryColor.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Vehicles Added',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Add your first vehicle to start\nbooking services and tracking\nmaintenance history.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddVehicleDialog(),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text(
                'Add Your First Vehicle',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclesList() {
    return RefreshIndicator(
      color: primaryColor,
      onRefresh: _loadVehicles,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _vehicles.length,
        itemBuilder: (context, index) {
          return _buildVehicleCard(_vehicles[index], index);
        },
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> vehicle, int index) {
    final make = vehicle['make'];
    final model = vehicle['model'];
    final year = vehicle['year']?.toString() ?? '';
    final plateNumber = vehicle['plateNumber'] ?? 'N/A';
    final status = vehicle['status'] ?? 'pending';
    final fuelType = vehicle['fuelType'];
    final displacement = vehicle['displacement']?.toString();
    final sizeClass = vehicle['sizeClass'];
    final submittedAt = vehicle['submittedAt'];
    final approvedAt = vehicle['approvedAt'];
    final adminNote = vehicle['adminNote'];

    Color statusColor = _getStatusColor(status);

    return GestureDetector(
      onTap: () {
        // Navigate to vehicle detail page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (context) => VehicleDetailPage(
                  vehicleData: {'vehicle': vehicle, 'userInfo': _userInfo},
                  onStatusUpdated: () {
                    // Refresh vehicles list when status is updated
                    _loadVehicles();
                  },
                  userId: widget.userId,
                  userName: widget.userName,
                ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Vehicle Image and Status
            Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor.withOpacity(0.8), primaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Stack(
                children: [
                  // Status Badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // Vehicle Image
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child:
                          make != 'Unknown' &&
                                  model != 'Unknown' &&
                                  year.isNotEmpty
                              ? Image.network(
                                'https://cdn.imagin.studio/getImage?customer=demo&make=$make&modelFamily=$model&modelYear=$year&angle=01',
                                height: 200,
                                width: 180,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) => Container(
                                      height: 80,
                                      width: 120,
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
                              )
                              : Container(
                                height: 80,
                                width: 120,
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

                  // Menu Button (only for approved vehicles)
                  if (status == 'approved' || status == 'pending')
                    Positioned(
                      top: 12,
                      left: 12,
                      child: PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteConfirmation(index);
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ),
                  if (status == 'rejected' || status == 'pending')
                    Positioned(
                      top: 12,
                      left: 12,
                      child: PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'edit') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => EditVehiclePage(
                                      userId: widget.userId,
                                      vehicle: vehicle,
                                      vehicleIndex: index,
                                      onVehicleUpdated: () {
                                        _loadVehicles();
                                      },
                                    ),
                              ),
                            );
                          }
                          if (value == 'delete') {
                            _showDeleteConfirmation(index);
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 18),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
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

            // Vehicle Details
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Info
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plateNumber,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: secondaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$make $model${year.isNotEmpty ? ' ($year)' : ''}',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Additional Details
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (fuelType != null)
                        _buildDetailChip(Icons.local_gas_station, fuelType),
                      if (displacement != null)
                        _buildDetailChip(Icons.settings, '${displacement}L'),
                      if (sizeClass != null)
                        _buildDetailChip(Icons.straighten, sizeClass),
                    ],
                  ),

                  // Status-specific content
                  if (status == 'pending') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hourglass_empty,
                            color: Colors.orange.shade600,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vehicle is under review by admin',
                              style: TextStyle(
                                color: Colors.orange.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (status == 'rejected' && adminNote != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.cancel,
                                color: Colors.red.shade600,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Rejected Reason: ',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adminNote,
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Submission date
                  if (submittedAt != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Submitted: ${_formatDate(submittedAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Text(
                    'Approved On: ${_formatDate(approvedAt)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is String) {
      date = DateTime.parse(timestamp);
    } else {
      return '';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  void _showAddVehicleDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddVehiclePage(
              userId: widget.userId,
              onVehicleAdded: _loadVehicles,
            ),
      ),
    );
  }

  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Vehicle'),
            content: const Text(
              'Are you sure you want to delete this vehicle? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteVehicle(index);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteVehicle(int index) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
      );

      final updatedVehicles = List<Map<String, dynamic>>.from(_vehicles);
      updatedVehicles.removeAt(index);

      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .update({'vehicles': updatedVehicles});

      // Close loading dialog
      Navigator.pop(context);

      await _loadVehicles();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete vehicle: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class AddVehiclePage extends StatefulWidget {
  final String userId;
  final VoidCallback onVehicleAdded;

  const AddVehiclePage({
    super.key,
    required this.userId,
    required this.onVehicleAdded,
  });

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  final _formKey = GlobalKey<FormState>();
  final _carOwnerNameController = TextEditingController();
  final _plateController = TextEditingController();
  final _vinController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final String _secretKey = "X9f@3LpZ7qW!m2CkT8r#Jd6vNb^Hs4Y0";
  late final encrypt.Key key;
  late final encrypt.Encrypter encrypter;

  String? _selectedMake;
  String? _selectedModel;
  String? _selectedYear;
  String? _selectedFuelType;
  String? _selectedSizeClass;
  String? _displacement;
  File? _vocImage;
  String? _vocImageUrl;

  List<String> _makes = [];
  List<String> _models = [];
  List<String> _years = [];
  List<String> _sizeClasses = [];

  bool _isLoading = false;
  bool _isLoadingMakes = true;
  bool _isLoadingModels = false;
  bool _isLoadingYears = false;
  bool _isLoadingSizeClasses = false;
  bool _isUploadingImage = false;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadMakes();
    key = encrypt.Key.fromUtf8(_secretKey);
    encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  Future<void> _loadMakes() async {
    try {
      setState(() => _isLoadingMakes = true);

      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .orderBy('createdAt', descending: true)
              .get();

      final makes =
          snapshot.docs.map((doc) => doc['make'].toString()).toSet().toList();

      makes.sort();
      setState(() {
        _makes = makes;
        _isLoadingMakes = false;
      });
    } catch (e) {
      setState(() => _isLoadingMakes = false);
      _showErrorSnackBar('Failed to load vehicle makes');
    }
  }

  Future<void> _loadModels(String make) async {
    try {
      setState(() => _isLoadingModels = true);

      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: make)
              .get();

      final models = <String>{};
      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          final fitments =
              (m['fitments'] is List) ? List.from(m['fitments']) : [];
          final hasApproved = fitments.any((f) => f['status'] == 'approved');
          if (hasApproved) {
            models.add(m['name']);
          }
        }
      }

      setState(() {
        _models = models.toList()..sort();
        _selectedModel = null;
        _selectedYear = null;
        _years.clear();
        _isLoadingModels = false;
      });
    } catch (e) {
      setState(() => _isLoadingModels = false);
      _showErrorSnackBar('Failed to load models');
    }
  }

  Future<void> _loadYears(String make, String model) async {
    try {
      setState(() => _isLoadingYears = true);

      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: make)
              .get();

      final years = <String>{};
      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          if (m['name'] == model) {
            final fitments = List.from(m['fitments'] ?? []);
            for (var f in fitments) {
              if (f['status'] == 'approved' && f['year'] != null) {
                years.add(f['year'].toString());
              }
            }
          }
        }
      }

      setState(() {
        _years =
            years.toList()
              ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
        _selectedYear = null;
        _isLoadingYears = false;
      });
    } catch (e) {
      setState(() => _isLoadingYears = false);
      _showErrorSnackBar('Failed to load years');
    }
  }

  Future<void> _loadSizeClasses(String make, String model, String year) async {
    try {
      setState(() => _isLoadingSizeClasses = true);

      final snapshot =
          await FirebaseFirestore.instance
              .collection('vehicles_list')
              .where('make', isEqualTo: make)
              .get();

      final sizeClasses = <String>{};
      String? foundDisplacement;
      String? foundFuelType;

      for (var doc in snapshot.docs) {
        final modelArray = List.from(doc['model'] ?? []);
        for (var m in modelArray) {
          if (m['name'] == model) {
            final fitments = List.from(m['fitments'] ?? []);
            for (var f in fitments) {
              if (f['status'] == 'approved' && f['year'] == year) {
                if (f['sizeClass'] != null) {
                  sizeClasses.add(f['sizeClass'].toString());
                }
                if (foundDisplacement == null && f['displacement'] != null) {
                  var displacement = f['displacement'].toString();
                  // Remove square brackets if displacement is an array string
                  if (displacement.startsWith('[') &&
                      displacement.endsWith(']')) {
                    displacement = displacement.substring(
                      1,
                      displacement.length - 1,
                    );
                  }
                  foundDisplacement = displacement;
                }
                if (foundFuelType == null && f['fuel'] != null) {
                  foundFuelType = f['fuel'].toString();
                }
              }
            }
          }
        }
      }

      setState(() {
        _sizeClasses = sizeClasses.toList()..sort();
        _displacement = foundDisplacement;
        _selectedFuelType = foundFuelType;
        if (_sizeClasses.length == 1) {
          _selectedSizeClass = _sizeClasses.first;
        }
        _isLoadingSizeClasses = false;
      });
    } catch (e) {
      setState(() => _isLoadingSizeClasses = false);
      _showErrorSnackBar('Failed to load size classes');
    }
  }

  Future<void> _pickVocImage() async {
    try {
      final ImageSource? source = await _showImageSourceDialog();
      if (source == null) return;

      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          _showErrorSnackBar('Image size must be less than 5MB');
          return;
        }

        setState(() {
          _vocImage = File(picked.path);
        });

        // Upload to Firebase Storage
        await _uploadVocImage();

        _showSuccessSnackBar('VOC document uploaded successfully');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _uploadVocImage() async {
    if (_vocImage == null) {
      _showErrorSnackBar("Please select a VOC file before uploading.");
      return;
    }

    setState(() => _isUploadingImage = true);

    try {
      // Encrypt image first
      final encryptedData = await encryptImage(_vocImage);

      final fileName =
          'voc_${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.enc';
      final ref = FirebaseStorage.instance.ref().child(
        'vehicle_documents/$fileName',
      );

      // Upload encrypted data as bytes
      await ref.putData(
        base64Decode(encryptedData["encrypted"]!), // convert back to bytes
        SettableMetadata(
          contentType: encryptedData["mimeType"],
          customMetadata: {"iv": encryptedData["iv"]!},
        ),
      );

      _vocImageUrl = await ref.getDownloadURL();
      _showSuccessSnackBar("VOC uploaded and encrypted successfully!");
    } catch (e) {
    } finally {
      setState(() => _isUploadingImage = false);
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return await showDialog<ImageSource>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Select Image Source'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
    );
  }

  Future<Map<String, String>> encryptImage(File? file) async {
    if (file == null) {
      throw Exception("No file selected to encrypt.");
    }

    try {
      // Detect MIME type safely
      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = "image/jpeg";
      if (ext == "png") mimeType = "image/png";

      // Convert bytes to base64 string
      final bytes = await file.readAsBytes();
      final base64Text = base64Encode(bytes);

      // Generate random IV (16 bytes)
      final iv = encrypt.IV.fromLength(16);

      // Encrypt base64 string
      final encrypted = encrypter.encrypt(base64Text, iv: iv);

      return {
        "encrypted": encrypted.base64,
        "iv": base64Encode(iv.bytes),
        "mimeType": mimeType,
      };
    } catch (e) {
      throw Exception("Image encryption failed: $e");
    }
  }

  Future<void> _submitVehicle() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fill in all required fields');
      return;
    }

    if (_vocImage == null) {
      _showErrorSnackBar('Please upload the VOC document');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload VOC image if not already uploaded
      if (_vocImage == null) {
        await _uploadVocImage();
      }

      final vocData = await encryptImage(_vocImage);

      // Create new vehicle data
      final vehicleData = {
        'carOwnerName': _carOwnerNameController.text.trim(),
        'make': _selectedMake,
        'model': _selectedModel,
        'year': _selectedYear,
        'fuelType': _selectedFuelType,
        'displacement': _displacement,
        'sizeClass': _selectedSizeClass,
        'plateNumber': _plateController.text.trim().toUpperCase(),
        'vin': _vinController.text.trim().toUpperCase(),
        'vocUrl': vocData["encrypted"],
        'vocType': vocData["mimeType"],
        'vocIv': vocData["iv"],
        'status': 'pending',
        'submittedAt': Timestamp.now(),
        // 'adminNote': null,
      };
      // Get current vehicles
      final doc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(widget.userId)
              .get();

      List<dynamic> currentVehicles = [];
      if (doc.exists) {
        currentVehicles = List.from(doc.data()?['vehicles'] ?? []);
      }

      currentVehicles.add(vehicleData);

      await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .update({'vehicles': currentVehicles});

      _showSuccessSnackBar(
        'Vehicle added successfully! Awaiting admin approval.',
      );
      widget.onVehicleAdded();
      Navigator.pop(context);
    } catch (e) {
      _showErrorSnackBar('Failed to add vehicle: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text(
          'Add Vehicle',
          style: TextStyle(
            color: secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: secondaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vehicle Information Section
              _buildSectionHeader('Vehicle Information'),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _carOwnerNameController,
                label: 'Car Owner Name',
                hint: 'Enter the Car Owner Name',
                textCapitalization: TextCapitalization.none,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'car owner name is required';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Make Dropdown
              _buildDropdownField(
                label: 'Vehicle Make',
                value: _selectedMake,
                items: _makes,
                isLoading: _isLoadingMakes,
                onChanged: (value) {
                  setState(() {
                    _selectedMake = value;
                    _selectedModel = null;
                    _selectedYear = null;
                    _selectedSizeClass = null;
                    _models.clear();
                    _years.clear();
                    _sizeClasses.clear();
                  });
                  if (value != null) _loadModels(value);
                },
              ),

              const SizedBox(height: 16),

              // Model Dropdown
              _buildDropdownField(
                label: 'Vehicle Model',
                value: _selectedModel,
                items: _models,
                isLoading: _isLoadingModels,
                enabled: _selectedMake != null,
                onChanged: (value) {
                  setState(() {
                    _selectedModel = value;
                    _selectedYear = null;
                    _selectedSizeClass = null;
                    _years.clear();
                    _sizeClasses.clear();
                  });
                  if (value != null) _loadYears(_selectedMake!, value);
                },
              ),

              const SizedBox(height: 16),

              // Year Dropdown
              _buildDropdownField(
                label: 'Year',
                value: _selectedYear,
                items: _years,
                isLoading: _isLoadingYears,
                enabled: _selectedModel != null,
                onChanged: (value) {
                  setState(() {
                    _selectedYear = value;
                    _selectedSizeClass = null;
                    _sizeClasses.clear();
                  });
                  if (value != null)
                    _loadSizeClasses(_selectedMake!, _selectedModel!, value);
                },
              ),

              const SizedBox(height: 16),

              // Size Class Dropdown
              _buildDropdownField(
                label: 'Size Class',
                value: _selectedSizeClass,
                items: _sizeClasses,
                isLoading: _isLoadingSizeClasses,
                enabled: _selectedYear != null,
                onChanged: (value) {
                  setState(() {
                    _selectedSizeClass = value;
                  });
                },
              ),

              const SizedBox(height: 24),

              // Vehicle Details Section
              _buildSectionHeader('Vehicle Details'),
              const SizedBox(height: 16),

              // plate number
              _buildTextField(
                controller: _plateController,
                label: 'Plate Number',
                hint: 'Enter your plate number',
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Plate Number is required';
                  }
                  if (value.trim().length < 3) {
                    return 'Plate Number must be at least 3 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // VIN
              _buildTextField(
                controller: _vinController,
                label: 'VIN',
                hint: 'Enter Vehicle Identification Number',
                textCapitalization: TextCapitalization.characters,
                maxLength: 17,
                validator: (value) {
                  if (value != null &&
                      value.trim().isNotEmpty &&
                      value.trim().length != 17) {
                    return 'VIN must be exactly 17 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Document Section
              _buildSectionHeader('Vehicle Documentation'),
              const SizedBox(height: 16),

              // VOC Document Upload
              _buildVocUploadSection(),

              // Auto-filled information
              if (_selectedFuelType != null || _displacement != null) ...[
                const SizedBox(height: 24),
                _buildSectionHeader('Vehicle Information'),
                const SizedBox(height: 16),
                _buildAutoFilledInfo(),
              ],

              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed:
                      _isLoading || _isUploadingImage ? null : _submitVehicle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isLoading
                          ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Submitting...'),
                            ],
                          )
                          : const Text(
                            'Submit for Approval',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 16),

              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your vehicle will be reviewed by our admin team. You will be notified once the review is complete.',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: secondaryColor,
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    bool isLoading = false,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: enabled ? cardColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: InputBorder.none,
            ),
            hint: Text(
              isLoading ? 'Loading...' : 'Select $label',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            items:
                items.map((item) {
                  return DropdownMenuItem<String>(
                    value: item,
                    child: Text(item),
                  );
                }).toList(),
            onChanged: enabled && !isLoading ? onChanged : null,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '$label is required';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int? maxLength,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: primaryColor, width: 2),
            ),
            filled: true,
            fillColor: cardColor,
          ),
          maxLength: maxLength,
          textCapitalization: textCapitalization,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildVocUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VOC (Vehicle Ownership Certificate)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isUploadingImage ? null : _pickVocImage,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color:
                  _vocImage != null
                      ? Colors.green.shade50
                      : Colors.grey.shade50,
              border: Border.all(
                color:
                    _vocImage != null
                        ? Colors.green.shade300
                        : Colors.grey.shade300,
                style: BorderStyle.solid,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                _isUploadingImage
                    ? const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: primaryColor),
                        SizedBox(height: 8),
                        Text('Uploading...'),
                      ],
                    )
                    : _vocImage != null
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade600,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'VOC Document Uploaded',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to change',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                    : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: Colors.grey.shade600,
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to upload VOC document',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Required for verification',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoFilledInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedFuelType != null)
            _buildInfoRow('Fuel Type', _selectedFuelType!),
          if (_displacement != null)
            _buildInfoRow('Engine Displacement', '${_displacement}L'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(color: Colors.green.shade600, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.green.shade700,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
