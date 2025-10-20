import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/navigation_map_service.dart';
import 'driver_navigation_map_page.dart';
import 'driver_towing_request_info.dart';
import '../../services/location_service.dart';
import '../../pages/towing_driver/driver_profile_page.dart';

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

class DriverHomePage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final String? userId;

  const DriverHomePage({super.key, this.userData, this.userId});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<QuerySnapshot>? _requestsSubscription;

  List<Map<String, dynamic>> _assignedRequests = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _currentDriverUid;
  String? _currentlyTrackingRequestId;
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuth();
      _startPeriodicLocationUpdates();
      _startRealTimeUpdates();
    });
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    _requestsSubscription?.cancel();
    LocationService.stopLocationUpdates();
    super.dispose();
  }

  void _startPeriodicLocationUpdates() {
    // Update location every 5 secs for dispatched requests
    _locationUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      final dispatchedRequests = _assignedRequests
          .where((request) => request['status'] == 'dispatched')
          .toList();

      for (final request in dispatchedRequests) {
        _loadDriverLocation(request['id']);
      }
    });
  }

  Future<void> _initializeAuth() async {
    try {
      _currentDriverUid =
          widget.userId ??
              widget.userData?['id'] ??
              widget.userData?['userId'] ??
              _auth.currentUser?.uid;

      await _loadAssignedRequests();
      _startLocationTrackingForDispatchedRequests();
    } catch (e) {
      debugPrint('Error initializing driver home: $e');
      setState(() => _isLoading = false);
    }
  }

  void _startRealTimeUpdates() {
    if (_currentDriverUid == null) return;

    _requestsSubscription = _firestore
        .collection('towing_requests')
        .where('driverId', isEqualTo: _currentDriverUid)
        .where('status', whereIn: ['dispatched', 'ongoing'])
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      for (final docChange in snapshot.docChanges) {
        if (docChange.type == DocumentChangeType.modified) {
          final updatedData = docChange.doc.data() as Map<String, dynamic>;
          final requestId = docChange.doc.id;

          // Find and update the local request
          final requestIndex = _assignedRequests.indexWhere((req) => req['id'] == requestId);
          if (requestIndex != -1) {
            setState(() {
              _assignedRequests[requestIndex] = {
                ..._assignedRequests[requestIndex],
                ...updatedData,
                'id': requestId,
              };
            });
          }
        }
      }
    });
  }

  void _startLocationTrackingForDispatchedRequests() {
    final dispatchedRequests = _assignedRequests
        .where((request) => request['status'] == 'dispatched' || request['status'] == 'ongoing')
        .toList();

    if (dispatchedRequests.isNotEmpty) {
      final latestRequest = dispatchedRequests.first;
      _startTrackingRequest(latestRequest['id']);
      if (latestRequest['status'] == 'dispatched') {
        _loadDriverLocation(latestRequest['id']);
      }
    }
  }

  Future<void> _loadAssignedRequests() async {
    try {
      if (_currentDriverUid == null) {
        debugPrint('No driver UID available');
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        return;
      }

      setState(() => _isLoading = true);

      final query = await _firestore
          .collection('towing_requests')
          .where('driverId', isEqualTo: _currentDriverUid)
          .where('status', whereIn: ['completed', 'dispatched', 'ongoing', 'accepted', 'invoice_generated'])
          .orderBy('createdAt', descending: true)
          .get();

      final requests = query.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, ...data};
      }).toList();

      setState(() {
        _assignedRequests = requests;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('Error loading requests: $e');
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to load requests',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _startTrackingRequest(String requestId) async {
    try {
      if (_currentlyTrackingRequestId != requestId) {
        await LocationService.stopLocationUpdates();
        _currentlyTrackingRequestId = requestId;

        await LocationService.startAutomaticLocationUpdates(
          requestId,
          widget.userData ?? {},
        );

        debugPrint('Started automatic location tracking for request: $requestId');
      }
    } catch (e) {
      debugPrint('Error starting location tracking: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to start location tracking',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _updateRequestStatus(
      String requestId,
      String newStatus,
      String notes,
      ) async {
    try {
      if (newStatus == 'ongoing') {
        final confirmed = await _showArrivalConfirmationDialog();
        if (!confirmed) {
          return;
        }
      }

      final timestamp = Timestamp.now();
      final statusUpdate = {
        'status': newStatus,
        'updatedAt': timestamp,
        'statusUpdatedBy': widget.userData?['name'] ?? 'Driver',
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': newStatus,
            'timestamp': timestamp,
            'updatedBy': widget.userData?['name'] ?? 'Driver',
            'notes': notes,
          },
        ]),
      };

      final timestamps = {};
      switch (newStatus) {
        case 'ongoing':
          timestamps['serviceStartedAt'] = timestamp;
          await _startTrackingRequest(requestId);
          break;
        case 'completed':
          timestamps['completedAt'] = timestamp;
          await LocationService.stopLocationUpdates();
          _currentlyTrackingRequestId = null;
          break;
        case 'dispatched':
          await _startTrackingRequest(requestId);
          break;
      }

      await _firestore.collection('towing_requests').doc(requestId).update({
        ...statusUpdate,
        ...timestamps,
      });

      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Status updated to ${_getStatusText(newStatus)}',
          type: SnackBarType.success,
        );
        _refreshRequests();
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to update status',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<bool> _showArrivalConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.location_on, color: AppColors.primaryColor, size: 24),
              const SizedBox(width: 8),
              Text(
                'Confirm Arrival',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Have you arrived at the customer\'s location and are ready to start the towing service?',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warningColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warningColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This will update the status to "Ongoing" and start service tracking.',
                        style: TextStyle(
                          color: AppColors.warningColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes, I Have Arrived'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 8,
        );
      },
    ) ?? false;
  }

  Future<void> _loadDriverLocation(String requestId) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'Please enable location services',
            type: SnackBarType.error,
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            CustomSnackBar.show(
              context: context,
              message: 'Location permission denied',
              type: SnackBarType.error,
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'Location permission permanently denied. Please enable it in settings.',
            type: SnackBarType.error,
          );
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Find the request to get customer location
      final requestIndex = _assignedRequests.indexWhere((req) => req['id'] == requestId);
      if (requestIndex == -1) return;

      final request = _assignedRequests[requestIndex];

      // Calculate distance and estimated time if customer location is available
      double? distance;
      int? estimatedTime;

      final customerLocation = request['location']?['customer'] as Map<String, dynamic>?;
      if (customerLocation != null) {
        final double? customerLat = customerLocation['latitude']?.toDouble();
        final double? customerLng = customerLocation['longitude']?.toDouble();

        if (customerLat != null && customerLng != null) {
          distance = NavigationMapService.calculateDistance(
            position.latitude,
            position.longitude,
            customerLat,
            customerLng,
          );

          estimatedTime = NavigationMapService.calculateEstimatedTime(distance);
        }
      }

      final driverLocation = {
        'towingDriver': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': Timestamp.now(),
          'contactNumber': widget.userData?['phoneNo'],
          'distanceToCustomer': distance,
         'estimatedArrivalTime': estimatedTime,
        },
      };

      // Prepare update data
      final updateData = {
        'location.towingDriver': driverLocation['towingDriver'],
        'updatedAt': Timestamp.now(),
      };

      // Add live tracking data if available
      if (distance != null && estimatedTime != null) {
        updateData['liveDistance'] = distance;
        updateData['estimatedDuration'] = estimatedTime;
        updateData['lastLocationUpdate'] = Timestamp.now();
      }

      await _firestore.collection('towing_requests').doc(requestId).update(updateData);

      if (mounted && distance != null && estimatedTime != null) {
        setState(() {
          _assignedRequests[requestIndex] = {
            ..._assignedRequests[requestIndex],
            'liveDistance': distance,
            'estimatedDuration': estimatedTime,
            'lastLocationUpdate': Timestamp.now(),
          };
        });
      }

    } catch (e) {
      debugPrint('Error sharing location: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to share location: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  void _showNavigationMap(Map<String, dynamic> request) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationMapPage(
          request: request,
          driverData: widget.userData,
        ),
      ),
    );
  }

  Future<void> _callCustomer(String phoneNumber) async {
    final url = 'tel:$phoneNumber';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Cannot make call',
          type: SnackBarType.error,
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warningColor;
      case 'accepted':
        return AppColors.primaryColor;
      case 'dispatched':
        return AppColors.accentColor;
      case 'ongoing':
        return AppColors.primaryDark;
      case 'invoice_generated':
        return AppColors.accentColor;
      case 'completed':
        return AppColors.successColor;
      case 'cancelled':
        return AppColors.errorColor;
      default:
        return AppColors.textMuted;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'dispatched':
        return 'Dispatched';
      case 'ongoing':
        return 'Ongoing';
      case 'invoice_generated':
        return 'Ready';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'N/A';
    return DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp.toDate());
  }

  Future<void> _refreshRequests() async {
    setState(() => _isRefreshing = true);
    await _loadAssignedRequests();
    final activeRequests = _assignedRequests
        .where((request) => request['status'] == 'dispatched' || request['status'] == 'ongoing')
        .toList();

    for (final request in activeRequests) {
      _loadDriverLocation(request['id']);
    }
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverProfilePage(
          userId: _currentDriverUid ?? widget.userId ?? '',
        ),
      ),
    );
  }

  void _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performLogout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        CustomSnackBar.show(
          context: context,
          message: 'Logged out successfully',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Logout failed: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  Widget _buildDriverTowingCard(Map<String, dynamic> request) {
    final status = request['status'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final isDispatched = status == 'dispatched';
    final isOngoing = status == 'ongoing';

    final liveDistance = request['liveDistance'] as double?;
    final estimatedDuration = request['estimatedDuration'] as int?;
    final lastUpdate = request['lastLocationUpdate'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppColors.borderColor),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'TOWING',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(request['createdAt'] as Timestamp?),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),

          if ((isDispatched || isOngoing) && LocationService.isTracking)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.successColor.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(color: AppColors.borderColor),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.successColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Location Tracking Active',
                    style: TextStyle(
                      color: AppColors.successColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer Request',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if ((isDispatched || isOngoing) && liveDistance != null && estimatedDuration != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentColor.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.accentColor.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 14, color: AppColors.accentColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Live Distance:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${liveDistance.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.timer, size: 14, color: AppColors.primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  'Estimated Arrival:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '$estimatedDuration min',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        if (lastUpdate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Updated ${_formatRelativeTime(lastUpdate)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                if ((isDispatched || isOngoing) && liveDistance != null && estimatedDuration != null)
                  const SizedBox(height: 12),

                if (request['vehicleInfo'] != null) ...[
                  Row(
                    children: [
                      Icon(Icons.directions_car, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${(request['vehicleInfo'] as Map<String, dynamic>)['make'] ?? ''} ${(request['vehicleInfo'] as Map<String, dynamic>)['model'] ?? ''} • ${(request['vehicleInfo'] as Map<String, dynamic>)['plateNumber'] ?? 'Unknown'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                Row(
                  children: [
                    Icon(Icons.local_shipping, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request['towingType'] ?? 'General Towing',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (request['location'] != null && (request['location'] as Map)['customer'] != null) ...[
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (request['location'] as Map)['customer']['address']['full'] ?? 'Location not specified',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estimated Cost:',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'RM ${request['estimatedCost'].toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      if (request['distance'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Initial Distance:',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${(request['distance'] as num).toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentColor,
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
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DriverRequestDetailsPage(
                            userId: widget.userId,
                            request: request,
                            userData: widget.userData,
                          ),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        backgroundColor: AppColors.primaryColor.withOpacity(0.1),
                      ),
                      child: const Text('View Details'),
                    ),
                    Row(
                      children: [
                        if (isDispatched || isOngoing)
                          IconButton(
                            onPressed: () => _showNavigationMap(request),
                            icon: Icon(
                              Icons.navigation,
                              color: AppColors.primaryDark,
                              size: 20,
                            ),
                            tooltip: 'Navigate to Customer',
                          ),

                        if (request['contactNumber'] != null && request['status'] != 'completed')
                          IconButton(
                            onPressed: () => _callCustomer(request['contactNumber']),
                            icon: Icon(
                              Icons.phone,
                              color: AppColors.successColor,
                              size: 20,
                            ),
                            tooltip: 'Call Customer',
                          ),

                        if (isDispatched)
                          IconButton(
                            onPressed: () => _updateRequestStatus(
                              request['id'],
                              'ongoing',
                              'Driver arrived at location and service started',
                            ),
                            icon: Icon(
                              Icons.play_arrow,
                              color: AppColors.warningColor,
                              size: 20,
                            ),
                            tooltip: 'Start Service',
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(Timestamp timestamp) {
    final now = DateTime.now();
    final time = timestamp.toDate();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'My Towing Assignments',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _navigateToProfile,
            icon: const Icon(Icons.person, color: Colors.white),
            tooltip: 'Profile',
          ),
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryColor),
            ),
            SizedBox(height: 16),
            Text(
              'Loading assigned requests...',
              style: TextStyle(color: AppColors.textMuted, fontSize: 16),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _refreshRequests,
        color: AppColors.primaryColor,
        child: _assignedRequests.isEmpty
            ? SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 100),
                Icon(
                  Icons.assignment_outlined,
                  size: 80,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 20),
                Text(
                  'No Active Assignments',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will see towing requests here when they are assigned to you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        )
            : Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Assignments (${_assignedRequests.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _assignedRequests.length,
                  itemBuilder: (context, index) {
                    return _buildDriverTowingCard(_assignedRequests[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isRefreshing
          ? FloatingActionButton(
        onPressed: null,
        backgroundColor: AppColors.primaryColor,
        child: const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      )
          : FloatingActionButton(
        onPressed: _refreshRequests,
        backgroundColor: AppColors.primaryColor,
        child: const Icon(Icons.refresh, color: Colors.white),
        tooltip: 'Refresh',
      ),
    );
  }
}