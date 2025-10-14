import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:automate_application/pages/my_vehicles/edit_vehicle_page.dart';

class VehicleDetailPage extends StatefulWidget {
  final Map<String, dynamic> vehicleData;
  final VoidCallback onStatusUpdated;
  final String userId;
  final String userName;

  const VehicleDetailPage({
    super.key,
    required this.vehicleData,
    required this.onStatusUpdated,
    required this.userId,
    required this.userName,
  });

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  State<VehicleDetailPage> createState() => _VehicleDetailPageState();
}

class _VehicleDetailPageState extends State<VehicleDetailPage> {
  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicleData['vehicle'];
    final userInfo = widget.vehicleData['userInfo'] ?? {};

    return Scaffold(
      backgroundColor: VehicleDetailPage.backgroundColor,
      appBar: AppBar(
        backgroundColor: VehicleDetailPage.cardColor,
        elevation: 0,
        title: const Text(
          'Vehicle Details',
          style: TextStyle(
            color: VehicleDetailPage.secondaryColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserInfoCard(userInfo),

            const SizedBox(height: 16),

            _buildVehicleInfoCard(vehicle),

            const SizedBox(height: 16),

            _buildServiceMaintenanceCard(vehicle),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(Map<String, dynamic> userInfo) {
    final name = userInfo['name'] ?? 'Unknown User';
    final email = userInfo['email'] ?? '';
    final phone = userInfo['phone'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VehicleDetailPage.cardColor,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: VehicleDetailPage.secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: VehicleDetailPage.primaryColor,
                radius: 25,
                child: Text(
                  name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.email,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleInfoCard(Map<String, dynamic> vehicle) {
    final carOwnerName = vehicle['carOwnerName'] ?? 'N/A';
    final make = vehicle['make'] ?? 'Unknown';
    final model = vehicle['model'] ?? 'Unknown';
    final year = vehicle['year']?.toString() ?? '';
    final plateNumber = vehicle['plateNumber'] ?? 'N/A';
    final vin = vehicle['vin'] ?? '';
    final fuelType = vehicle['fuelType'];
    final displacement = vehicle['displacement'];
    final sizeClass = vehicle['sizeClass'];
    final submittedAt = vehicle['submittedAt'] as Timestamp?;
    final approvedAt = vehicle['approvedAt'] as Timestamp?;
    final adminNote = vehicle['adminNote'];
    final status = vehicle['status'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: VehicleDetailPage.cardColor,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: VehicleDetailPage.secondaryColor,
            ),
          ),
          const SizedBox(height: 16),

          _buildInfoRow('Car Owner Name', carOwnerName, Icons.person),
          // Plate number
          _buildInfoRow('Plate Number', plateNumber, Icons.confirmation_number),

          // Vehicle Details
          _buildInfoRow('Make', make, Icons.directions_car),
          _buildInfoRow('Model', model, Icons.model_training),
          if (year.isNotEmpty)
            _buildInfoRow('Year', year, Icons.calendar_today),

          // VIN
          if (vin.isNotEmpty) _buildInfoRow('VIN', vin, Icons.fingerprint),

          // Engine Details
          if (fuelType != null)
            _buildInfoRow('Fuel Type', fuelType, Icons.local_gas_station),
          if (displacement != null)
            _buildInfoRow('Displacement', '${displacement}L', Icons.settings),
          if (sizeClass != null)
            _buildInfoRow('Size Class', sizeClass, Icons.straighten),

          // Submission Details
          if (submittedAt != null) ...[
            const Divider(height: 32),
            _buildInfoRow(
              'Submitted On',
              _formatDateTime(submittedAt.toDate()),
              Icons.schedule,
            ),
            const SizedBox(height: 6),
          ],
          if (approvedAt != null) ...[
            _buildInfoRow(
              'Approved On',
              _formatDateTime(approvedAt.toDate()),
              Icons.schedule,
            ),
          ],
          if (status == 'rejected') ...[
            _buildInfoRow(
              'Rejected Reason: ',
              adminNote,
              Icons.edit_note,
            )
          ]
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceMaintenanceCard(Map<String, dynamic> vehicle) {
    final serviceMaintenances = List<Map<String, dynamic>>.from(
        vehicle['serviceMaintenances'] ?? []
    );

    // Get all available service types from your predefined list
    final allServiceTypes = _serviceTypeDisplayNames.keys.toList();

    // Find missing service types that haven't been added yet
    final existingServiceTypes = serviceMaintenances
        .map((m) => m['serviceType']?.toString())
        .whereType<String>()
        .toSet(); // Use Set for better performance

    final missingServiceTypes = allServiceTypes
        .where((type) => !existingServiceTypes.contains(type))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: VehicleDetailPage.cardColor,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Service Maintenance Schedule',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: VehicleDetailPage.secondaryColor,
                ),
              ),
              if (missingServiceTypes.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.add, color: VehicleDetailPage.primaryColor),
                  onPressed: () {
                    _showAddServiceMaintenanceDialog(widget.userId, widget.userName);
                  },
                  tooltip: 'Add Missing Service',
                ),
            ],
          ),
          const SizedBox(height: 16),

          if (serviceMaintenances.isEmpty && missingServiceTypes.isEmpty)
            _buildEmptyServiceMaintenanceState()
          else if (serviceMaintenances.isEmpty)
            _buildNoServicesAddedState(missingServiceTypes)
          else
            Column(
              children: [
                ...serviceMaintenances.map((maintenance) =>
                    _buildMaintenanceItem(maintenance)
                ).toList(),

                // Show missing services section if there are any
                if (missingServiceTypes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildMissingServicesSection(missingServiceTypes),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildNoServicesAddedState(List<String> missingServiceTypes) {
    return Column(
      children: [
        const Center(
          child: Column(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'No service maintenance records yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Add your first service maintenance schedule',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildMissingServicesSection(missingServiceTypes),
      ],
    );
  }

  Widget _buildEmptyServiceMaintenanceState() {
    return Column(
      children: [
        const Center(
          child: Column(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'No service maintenance records yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Add your service maintenance schedule at the initial stage',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              _showAddServiceMaintenanceDialog(widget.userId, widget.userName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VehicleDetailPage.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 20),
                SizedBox(width: 8),
                Text(
                  'Add Service Maintenance',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddServiceMaintenanceDialog(String userId, String userName) {
    final vehicle = widget.vehicleData['vehicle'];
    final vehicleId = vehicle['plateNumber'] ?? '';
    final existingServices = List<Map<String, dynamic>>.from(
        vehicle['serviceMaintenances'] ?? []
    );

    showDialog(
      context: context,
      builder: (context) => AddServiceMaintenanceDialog(
        key: const Key('add_service_dialog'),
        userId: widget.userId,
        userName: widget.userName,
        vehicleId: vehicleId,
        existingServices: existingServices,
        onServiceAdded: widget.onStatusUpdated,
      ),
    );
  }

  Widget _buildMissingServicesSection(List<String> missingServiceTypes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Services to Add:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: VehicleDetailPage.secondaryColor,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: missingServiceTypes.map((serviceType) {
            return ActionChip(
              label: Text(_serviceTypeDisplayNames[serviceType] ?? serviceType),
              onPressed: () {
                _showAddSpecificServiceDialog(serviceType);
              },
              backgroundColor: VehicleDetailPage.primaryColor.withOpacity(0.1),
              labelStyle: TextStyle(
                color: VehicleDetailPage.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showAddSpecificServiceDialog(String serviceType) {
    final vehicle = widget.vehicleData['vehicle'];
    final vehicleId = vehicle['plateNumber'] ?? '';
    final existingServices = List<Map<String, dynamic>>.from(
        vehicle['serviceMaintenances'] ?? []
    );

    showDialog(
      context: context,
      builder: (context) => AddServiceMaintenanceDialog(
        key: const Key('add_specific_service_dialog'),
        userId: widget.userId,
        userName: widget.userName,
        vehicleId: vehicleId,
        existingServices: existingServices,
        preSelectedServiceType: serviceType,
        onServiceAdded: widget.onStatusUpdated,
      ),
    );
  }

  Widget _buildMaintenanceItem(Map<String, dynamic> maintenance) {
    final serviceType = maintenance['serviceType'] ?? '';
    final lastServiceMileage = maintenance['lastServiceMileage'] ?? 0;
    final nextServiceMileage = maintenance['nextServiceMileage'] ?? 0;
    final nextServiceDate = maintenance['nextServiceDate'] ?? '';
    final mileageUpdatedAt = maintenance['mileageUpdatedAt'] as Timestamp?;
    final updatedBy = maintenance['updatedBy'] ?? 'System';
    final remainingMileage = nextServiceMileage - lastServiceMileage;
    final nextDate = DateTime.tryParse(nextServiceDate);
    final today = DateTime.now();
    final remainingDays = nextDate != null ? nextDate.difference(today).inDays : 0;

    Color statusColor = Colors.green;
    if (remainingMileage <= 500 || (remainingDays <= 7 && remainingDays >= 0)) {
      statusColor = Colors.orange;
    }
    if (remainingMileage <= 0 || remainingDays < 0) {
      statusColor = Colors.red;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _getServiceTypeDisplayName(serviceType),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      remainingMileage <= 0 || remainingDays < 0 ?
                      'OVERDUE' : 'DUE SOON',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 18),
                    itemBuilder: (context) => [
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
                            Icon(Icons.delete, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showEditServiceMaintenanceDialog(maintenance);
                      } else if (value == 'delete') {
                        _showDeleteConfirmationDialog(maintenance);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMaintenanceDetailRow(
            'Last Service',
            '$lastServiceMileage km',
            Icons.settings,
          ),
          _buildMaintenanceDetailRow(
            'Next Service',
            '$nextServiceMileage km',
            Icons.arrow_forward,
          ),
          _buildMaintenanceDetailRow(
            'Remaining',
            '$remainingMileage km',
            Icons.trending_up,
          ),
          if (nextDate != null) ...[
            _buildMaintenanceDetailRow(
              'Due Date',
              _formatDate(nextDate),
              Icons.calendar_today,
            ),
            _buildMaintenanceDetailRow(
              'Days Left',
              '$remainingDays days',
              Icons.schedule,
            ),
          ],
          _buildMaintenanceDetailRow(
            'Updated By',
            updatedBy,
            Icons.person,
          ),
          if (mileageUpdatedAt != null)
            _buildMaintenanceDetailRow(
              'Last Updated',
              _formatDateTime(mileageUpdatedAt.toDate()),
              Icons.update,
            ),
        ],
      ),
    );
  }

  void _showEditServiceMaintenanceDialog(Map<String, dynamic> maintenance) {
    final vehicle = widget.vehicleData['vehicle'];
    final vehicleId = vehicle['plateNumber'] ?? '';
    final existingServices = List<Map<String, dynamic>>.from(
        vehicle['serviceMaintenances'] ?? []
    );

    showDialog(
      context: context,
      builder: (context) => AddServiceMaintenanceDialog(
        key: const Key('edit_service_dialog'),
        userId: widget.userId,
        userName: widget.userName,
        vehicleId: vehicleId,
        existingServices: existingServices,
        existingMaintenance: maintenance,
        onServiceAdded: widget.onStatusUpdated,
      ),
    );
  }

  void _showDeleteConfirmationDialog(Map<String, dynamic> maintenance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service Maintenance'),
        content: Text(
          'Are you sure you want to delete ${_getServiceTypeDisplayName(maintenance['serviceType'] ?? '')}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _deleteServiceMaintenance(maintenance);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteServiceMaintenance(Map<String, dynamic> maintenance) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      final vehicles = userDoc.data()?['vehicles'] as List? ?? [];
      final vehicleIndex = vehicles.indexWhere((v) =>
      v['plateNumber'] == widget.vehicleData['vehicle']['plateNumber']);

      if (vehicleIndex != -1) {
        final updatedVehicles = List.from(vehicles);
        final vehicle = Map<String, dynamic>.from(updatedVehicles[vehicleIndex]);

        final currentServices = List<Map<String, dynamic>>.from(
            vehicle['serviceMaintenances'] ?? []);

        // Remove the maintenance item
        currentServices.removeWhere((item) =>
        item['serviceType'] == maintenance['serviceType']);

        vehicle['serviceMaintenances'] = currentServices;
        updatedVehicles[vehicleIndex] = vehicle;

        await FirebaseFirestore.instance
            .collection('car_owners')
            .doc(widget.userId)
            .update({'vehicles': updatedVehicles});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service maintenance deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onStatusUpdated();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete service maintenance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMaintenanceDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, String> _serviceTypeDisplayNames = {
    'engine_oil': 'Engine Oil Change',
    'alignment': 'Wheel Alignment',
    'battery': 'Battery Replacement',
    'tire_rotation': 'Tire Rotation',
    'brake_fluid': 'Brake Fluid Change',
    'air_filter': 'Air Filter Replacement',
    'coolant': 'Coolant Flush',
    'gear_oil': 'Gear Oil Change',
    'at_fluid': 'AT Fluid Change',
  };

  String _getServiceTypeDisplayName(String serviceType) {
    final displayNames = {
      'engine_oil': 'Engine Oil Change',
      'alignment': 'Wheel Alignment',
      'battery': 'Battery Replacement',
      'tire_rotation': 'Tire Rotation',
      'brake_fluid': 'Brake Fluid Change',
      'air_filter': 'Air Filter Replacement',
      'coolant': 'Coolant Flush',
      'gear_oil': 'Gear Oil',
      'at_fluid': 'AT Fluid',
    };
    return displayNames[serviceType] ?? serviceType.replaceAll('_', ' ').toUpperCase();
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}

class AddServiceMaintenanceDialog extends StatefulWidget {
  final String userId;
  final String userName;
  final String vehicleId;
  final VoidCallback onServiceAdded;
  final String? preSelectedServiceType;
  final Map<String, dynamic>? existingMaintenance;
  final List<Map<String, dynamic>>? existingServices;

  const AddServiceMaintenanceDialog({
    super.key,
    required this.userId,
    required this.userName,
    required this.vehicleId,
    required this.onServiceAdded,
    this.preSelectedServiceType,
    this.existingMaintenance,
    this.existingServices,
  });

  @override
  State<AddServiceMaintenanceDialog> createState() => _AddServiceMaintenanceDialogState();
}

class _AddServiceMaintenanceDialogState extends State<AddServiceMaintenanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _serviceData = {
    'serviceType': '',
    'lastServiceMileage': 0,
    'nextServiceMileage': 0,
    'nextServiceDate': '',
  };

  final List<String> _serviceTypes = [
    'engine_oil',
    'alignment',
    'battery',
    'tire_rotation',
    'brake_fluid',
    'air_filter',
    'coolant',
    'gear_oil',
    'at_fluid',
  ];

  final Map<String, String> _serviceTypeDisplayNames = {
    'engine_oil': 'Engine Oil Change',
    'alignment': 'Wheel Alignment',
    'battery': 'Battery Replacement',
    'tire_rotation': 'Tire Rotation',
    'brake_fluid': 'Brake Fluid Change',
    'air_filter': 'Air Filter Replacement',
    'coolant': 'Coolant Flush',
    'gear_oil': 'Gear Oil Change',
    'at_fluid': 'AT Fluid Change',
  };

  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingMaintenance != null;

    // Pre-fill data if editing
    if (_isEditing && widget.existingMaintenance != null) {
      final maintenance = widget.existingMaintenance!;
      _serviceData['serviceType'] = maintenance['serviceType'] ?? '';
      _serviceData['lastServiceMileage'] = maintenance['lastServiceMileage'] ?? 0;
      _serviceData['nextServiceMileage'] = maintenance['nextServiceMileage'] ?? 0;

      final nextServiceDate = maintenance['nextServiceDate'] ?? '';
      if (nextServiceDate.isNotEmpty) {
        try {
          _selectedDate = DateTime.parse(nextServiceDate);
          _serviceData['nextServiceDate'] = nextServiceDate;
        } catch (e) {
          print('Error parsing date: $e');
        }
      }
    } else if (widget.preSelectedServiceType != null) {
      // Pre-select service type if provided
      _serviceData['serviceType'] = widget.preSelectedServiceType!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? 'Edit Service Maintenance' : 'Add Service Maintenance',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: VehicleDetailPage.secondaryColor,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service Type Dropdown (disabled when editing)
              _buildServiceTypeDropdown(),
              const SizedBox(height: 16),

              // Last Service Mileage
              _buildNumberField(
                label: 'Last Service Mileage (km)',
                initialValue: _serviceData['lastServiceMileage'].toString(),
                onSaved: (value) {
                  _serviceData['lastServiceMileage'] = int.tryParse(value ?? '0') ?? 0;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter last service mileage';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Next Service Mileage
              _buildNumberField(
                label: 'Next Service Mileage (km)',
                initialValue: _serviceData['nextServiceMileage'].toString(),
                onSaved: (value) {
                  _serviceData['nextServiceMileage'] = int.tryParse(value ?? '0') ?? 0;
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter next service mileage';
                  }
                  if (int.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _buildDatePicker(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_isEditing) // Show delete button when editing
          TextButton(
            onPressed: _isLoading ? null : _deleteServiceMaintenance,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addServiceMaintenance,
          style: ElevatedButton.styleFrom(
            backgroundColor: VehicleDetailPage.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          )
              : Text(_isEditing ? 'Update' : 'Add Service'),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Next Service Date',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: _selectDate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  _selectedDate != null
                      ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                      : 'Select date',
                  style: TextStyle(
                    color: _selectedDate != null ? Colors.black : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _serviceData['nextServiceDate'] = picked.toIso8601String().split('T')[0];
      });
    }
  }

  Widget _buildServiceTypeDropdown() {
    final existingServiceTypes = (widget.existingServices ?? [])
        .map((m) => m['serviceType']?.toString())
        .whereType<String>()
        .toSet();

    // Filter available service types to only show missing ones
    final availableServiceTypes = _serviceTypes
        .where((type) => !existingServiceTypes.contains(type))
        .toList();

    // If editing, include the current service type even if it exists
    final filteredServiceTypes = _isEditing
        ? _serviceTypes
        : availableServiceTypes;

    // If no services available to add, show message
    if (filteredServiceTypes.isEmpty && !_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Service Type',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              'All service types have been added. Use "Edit" to modify existing services.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Service Type',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      value: _serviceData['serviceType'].isEmpty ? null : _serviceData['serviceType'],
      items: filteredServiceTypes.map((String type) {
        return DropdownMenuItem(
          value: type,
          child: Text(_serviceTypeDisplayNames[type] ?? type),
        );
      }).toList(),
      onChanged: _isEditing ? null : (String? newValue) {
        setState(() {
          _serviceData['serviceType'] = newValue ?? '';
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please select a service type';
        }
        return null;
      },
    );
  }

  Widget _buildNumberField({
    required String label,
    required FormFieldSetter<String> onSaved,
    required FormFieldValidator<String> validator,
    String initialValue = '',
  }) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: TextInputType.number,
      initialValue: initialValue,
      onSaved: onSaved,
      validator: validator,
    );
  }

  Future<void> _addServiceMaintenance() async {
    if (!_formKey.currentState!.validate()) return;

    _formKey.currentState!.save();

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service date'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _saveServiceMaintenance();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service maintenance added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
        widget.onServiceAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add service maintenance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveServiceMaintenance() async {
    final serviceMaintenance = {
      'serviceType': _serviceData['serviceType'],
      'lastServiceMileage': _serviceData['lastServiceMileage'],
      'nextServiceMileage': _serviceData['nextServiceMileage'],
      'nextServiceDate': _serviceData['nextServiceDate'],
      'mileageUpdatedAt': Timestamp.now(),
      'updatedBy': widget.userName,
    };

    final userDoc = await FirebaseFirestore.instance
        .collection('car_owners')
        .doc(widget.userId)
        .get();

    final vehicles = userDoc.data()?['vehicles'] as List? ?? [];
    final vehicleIndex = vehicles.indexWhere((v) => v['plateNumber'] == widget.vehicleId);

    if (vehicleIndex == -1) {
      throw Exception('Vehicle ${widget.vehicleId} not found');
    }

    final updatedVehicles = List.from(vehicles);
    final vehicle = Map<String, dynamic>.from(updatedVehicles[vehicleIndex]);
    final currentServices = List<Map<String, dynamic>>.from(vehicle['serviceMaintenances'] ?? []);

    if (_isEditing && widget.existingMaintenance != null) {
      // Update existing maintenance
      final existingIndex = currentServices.indexWhere(
              (item) => item['serviceType'] == widget.existingMaintenance!['serviceType']
      );

      if (existingIndex != -1) {
        currentServices[existingIndex] = serviceMaintenance;
      } else {
        currentServices.add(serviceMaintenance);
      }
    } else {
      // Add new maintenance
      currentServices.add(serviceMaintenance);
    }

    vehicle['serviceMaintenances'] = currentServices;
    updatedVehicles[vehicleIndex] = vehicle;

    await FirebaseFirestore.instance
        .collection('car_owners')
        .doc(widget.userId)
        .update({'vehicles': updatedVehicles});
  }

  Future<void> _deleteServiceMaintenance() async {
    if (widget.existingMaintenance == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('car_owners')
          .doc(widget.userId)
          .get();

      final vehicles = userDoc.data()?['vehicles'] as List? ?? [];
      final vehicleIndex = vehicles.indexWhere((v) => v['plateNumber'] == widget.vehicleId);

      if (vehicleIndex != -1) {
        final updatedVehicles = List.from(vehicles);
        final vehicle = Map<String, dynamic>.from(updatedVehicles[vehicleIndex]);
        final currentServices = List<Map<String, dynamic>>.from(vehicle['serviceMaintenances'] ?? []);

        currentServices.removeWhere((item) =>
        item['serviceType'] == widget.existingMaintenance!['serviceType']);

        vehicle['serviceMaintenances'] = currentServices;
        updatedVehicles[vehicleIndex] = vehicle;

        await FirebaseFirestore.instance
            .collection('car_owners')
            .doc(widget.userId)
            .update({'vehicles': updatedVehicles});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service maintenance deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
          widget.onServiceAdded();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete service maintenance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}