import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'package:intl/intl.dart';

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

  List<Map<String, dynamic>> _assignedRequests = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _currentDriverUid;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF344370);
  static const Color backgroundColor = Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    // Delay initialization to ensure BuildContext is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAuth();
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
    } catch (e) {
      debugPrint('Error initializing driver home: $e');
      setState(() => _isLoading = false);
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

      final query =
          await _firestore
              .collection('towing_requests')
              .where('driverId', isEqualTo: _currentDriverUid)
              .orderBy('createdAt', descending: true)
              .get();


      final requests =
          query.docs.map((doc) {
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

  Future<void> _assignTestRequest() async {
    try {
      if (_currentDriverUid == null) {
        CustomSnackBar.show(
          context: context,
          message: 'Not authenticated. Please login again.',
          type: SnackBarType.error,
        );
        return;
      }

      final nullDriverRequests =
          await _firestore
              .collection('towing_requests')
              .where('driverId', isNull: true)
              .limit(1)
              .get();

      if (nullDriverRequests.docs.isNotEmpty) {
        final requestDoc = nullDriverRequests.docs.first;
        final requestData = requestDoc.data();

        await _firestore
            .collection('towing_requests')
            .doc(requestDoc.id)
            .update({
              'driverId': _currentDriverUid,
              'driverInfo': {
                'name': widget.userData?['name'] ?? 'Test Driver',
                'phoneNo': widget.userData?['phoneNo'] ?? 'N/A',
                'carPlate': widget.userData?['carPlate'] ?? 'N/A',
                'make': widget.userData?['make'] ?? 'N/A',
                'model': widget.userData?['model'] ?? 'N/A',
                'year': widget.userData?['year'] ?? 'N/A',
              },
            });

        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'Test request assigned successfully! Refreshing...',
            type: SnackBarType.success,
          );
          // Refresh the list
          _refreshRequests();
        }
      } else {
        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'No unassigned requests found',
            type: SnackBarType.warning,
          );
        }
      }
    } catch (e) {
      debugPrint('Error assigning test request: $e');
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'Failed to assign test request: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _refreshRequests() async {
    setState(() => _isRefreshing = true);
    await _loadAssignedRequests();
  }

  void _handleLogout() async {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
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

  Widget _buildRequestCard(Map<String, dynamic> request, int index) {
    final contactNumber = request['contactNumber'] ?? 'Not provided';
    final createdAt = request['createdAt'] as Timestamp?;
    final description = request['description'] ?? 'No description provided';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showRequestDetails(request),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Contact: $contactNumber',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: secondaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (createdAt != null)
                    Text(
                      DateFormat('MMM dd, HH:mm').format(createdAt.toDate()),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Assigned',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRequestDetails(Map<String, dynamic> request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _buildRequestDetailsSheet(request),
    );
  }

  Widget _buildRequestDetailsSheet(Map<String, dynamic> request) {
    final contactNumber = request['contactNumber'] ?? 'Not provided';
    final createdAt = request['createdAt'] as Timestamp?;
    final description = request['description'] ?? 'No description';
    final distance = request['distance']?.toString() ?? 'Not calculated';
    final driverInfo = request['driverInfo'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Towing Request Details',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: secondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          _buildDetailRow('Contact Number', contactNumber),
          const SizedBox(height: 12),
          if (createdAt != null) ...[
            _buildDetailRow(
              'Request Time',
              DateFormat('MMM dd, yyyy - hh:mm a').format(createdAt.toDate()),
            ),
            const SizedBox(height: 12),
          ],
          _buildDetailRow('Description', description),
          const SizedBox(height: 12),
          _buildDetailRow('Distance', '$distance km'),
          if (driverInfo != null) ...[
            const SizedBox(height: 20),
            const Text(
              'Driver Information:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: secondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            _buildDriverInfo(driverInfo),
          ],
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildDriverInfo(Map<String, dynamic> driverInfo) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoItem('Name', driverInfo['name'] ?? 'N/A'),
          _buildInfoItem('Phone', driverInfo['phoneNo'] ?? 'N/A'),
          _buildInfoItem('Car Plate', driverInfo['carPlate'] ?? 'N/A'),
          _buildInfoItem(
            'Vehicle',
            '${driverInfo['make'] ?? ''} ${driverInfo['model'] ?? ''}'.trim(),
          ),
          _buildInfoItem('Year', driverInfo['year']?.toString() ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Assigned Towing Requests',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading assigned requests...',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _refreshRequests,
                color: primaryColor,
                child:
                    _assignedRequests.isEmpty
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
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'No Assigned Requests',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_currentDriverUid != null)
                                  Text(
                                    'Your UID: $_currentDriverUid',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  'Requests need to be assigned to your UID to appear here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: _assignTestRequest,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                  ),
                                  child: const Text('Assign Test Request'),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _refreshRequests,
                                  child: const Text('Refresh'),
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
                                'Your Assigned Requests (${_assignedRequests.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _assignedRequests.length,
                                  itemBuilder: (context, index) {
                                    return _buildRequestCard(
                                      _assignedRequests[index],
                                      index,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
              ),
      floatingActionButton:
          _isRefreshing
              ? FloatingActionButton(
                onPressed: null,
                backgroundColor: primaryColor,
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
              : FloatingActionButton(
                onPressed: _refreshRequests,
                backgroundColor: primaryColor,
                child: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Refresh',
              ),
    );
  }
}
