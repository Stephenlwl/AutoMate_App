import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:automate_application/pages/my_vehicles/edit_vehicle_page.dart';

// Vehicle Detail Page
class VehicleDetailPage extends StatelessWidget {
  final Map<String, dynamic> vehicleData;
  final VoidCallback onStatusUpdated;

  const VehicleDetailPage({
    super.key,
    required this.vehicleData,
    required this.onStatusUpdated,
  });

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    final vehicle = vehicleData['vehicle'];
    final userInfo = vehicleData['userInfo'];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: const Text(
          'Vehicle Details',
          style: TextStyle(
            color: secondaryColor,
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
            // User Information Card
            _buildUserInfoCard(userInfo),

            const SizedBox(height: 16),

            // Vehicle Information Card
            _buildVehicleInfoCard(vehicle),

            const SizedBox(height: 16),

            // Service Maintenance Card
            _buildServiceMaintenanceCard(vehicle),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoCard(Map<String, dynamic> userInfo) {
    final name = userInfo['name'];
    final email = userInfo['email'] ?? '';
    final phone = userInfo['phone'];

    return Container(
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: primaryColor,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vehicle Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: secondaryColor,
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

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Maintenance Schedule',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 16),

          if (serviceMaintenances.isEmpty)
            const Center(
              child: Text(
                'No service maintenance records yet',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            )
          else
            ...serviceMaintenances.map((maintenance) =>
                _buildMaintenanceItem(maintenance)
            ).toList(),
        ],
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

    // Calculate remaining mileage/days
    final currentMileage = maintenance['currentMileage'] ?? lastServiceMileage;
    final remainingMileage = nextServiceMileage - currentMileage;
    final nextDate = DateTime.tryParse(nextServiceDate);
    final today = DateTime.now();
    final remainingDays = nextDate != null ?
    nextDate.difference(today).inDays : 0;

    // Determine status color
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
              Text(
                _getServiceTypeDisplayName(serviceType),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
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

  String _getServiceTypeDisplayName(String serviceType) {
    final displayNames = {
      'engine_oil': 'Engine Oil Change',
      'alignment': 'Wheel Alignment',
      'battery': 'Battery Replacement',
      'tire_rotation': 'Tire Rotation',
      'brake_fluid': 'Brake Fluid Change',
      'air_filter': 'Air Filter Replacement',
      'coolant': 'Coolant Flush',
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
