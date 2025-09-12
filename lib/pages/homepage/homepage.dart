import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:automate_application/pages/chat/message_chat_list_page.dart';
import 'package:automate_application/pages/chat/chat_page.dart';
import 'package:automate_application/services/chat_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  String? plateNumber, make, model, year, variant;
  String? fuelType, displacement, sizeClass;

  // Appointment, Payment, Review
  String? apptStatus, apptDateStr, apptCenterName;
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
      await Future.wait([
        _loadLatestAppointment(userId),
        _loadOutstandingPayment(userId),
        _loadLatestReview(userId),
        _loadLocation(),
      ]);
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

      // Vehicle fields
      if (data['vehicles'] != null) {
        final vehicles = List<Map<String, dynamic>>.from(
          data['vehicles'] as List,
        );
        if (vehicles.isNotEmpty) {
          final vehicle = vehicles.first;
          plateNumber = vehicle['plate_number'] as String?;
          make = vehicle['brand'] as String?;
          model = vehicle['model'] as String?;
          year = vehicle['year']?.toString();
          variant = vehicle['variant'] as String?;
          fuelType = vehicle['fuel_type'] as String?;
          displacement = vehicle['displacement']?.toString();
          sizeClass = vehicle['size_class'] as String?;
        }
      }
    } catch (e) {
      debugPrint('Owner/Vehicle loading error: $e');
    }
  }

  Future<void> _loadLatestAppointment(String uid) async {
    try {
      final apptQuerySnapshot =
          await FirebaseFirestore.instance
              .collection('service_bookings')
              .where('carOwnerId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (apptQuerySnapshot.docs.isNotEmpty) {
        final apptData = apptQuerySnapshot.docs.first.data();
        apptStatus = apptData['status'];

        final preferredDate = apptData['preferredDate'] as Timestamp?;
        if (preferredDate != null) {
          final date = preferredDate.toDate();
          apptDateStr = '${date.day}/${date.month}/${date.year}';
        }

        final scQuerySnapshot =
            await FirebaseFirestore.instance
                .collection('service_centers')
                .where('id', isEqualTo: apptData['serviceCenterId'])
                .limit(1)
                .get();
        if (scQuerySnapshot.docs.isNotEmpty) {
          final scData = scQuerySnapshot.docs.first.data();
          apptCenterName = scData['serviceCenterName'] ?? 'Service Center';
        }
      }
    } catch (e) {
      debugPrint('Appointment loading error: $e');
    }
  }

  Future<void> _loadOutstandingPayment(String uid) async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('payments')
              .where('carOwnerId', isEqualTo: uid)
              .where('status', isEqualTo: 'pending')
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        paymentAmount = data['amount'];
        paymentStatus = data['status'];

        final dueDate = data['dueDate'] as Timestamp?;
        if (dueDate != null) {
          final date = dueDate.toDate();
          paymentDueStr = '${date.day}/${date.month}/${date.year}';
        }
      }
    } catch (e) {
      debugPrint('Payment loading error: $e');
    }
  }

  Future<void> _loadLatestReview(String uid) async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('reviews')
              .where('carOwnerId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        reviewRating = data['rating']?.toDouble();
        reviewComment = data['comment'];
        reviewCenterName = data['serviceCenterName'];
      }
    } catch (e) {
      debugPrint('Review loading error: $e');
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
        IconButton(
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
            // Navigate to notifications
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
    return Container(
      padding: const EdgeInsets.all(10),
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
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child:
                (make != null && model != null && year != null)
                    ? Image.network(
                      'https://cdn.imagin.studio/getImage?customer=demo&make=$make&modelFamily=$model&modelYear=$year&angle=01',
                      height: 150,
                      width: 130,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (context, error, stackTrace) => Container(
                            height: 130,
                            width: 110,
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
                      height: 150,
                      width: 130,
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
                const Text(
                  'Your Vehicle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
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
            onPressed: () {

            },
          ),
        ],
      ),
    );
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
        'label': 'Emergency/Towing',
        'icon': Icons.emergency_outlined,
        'color': Colors.red,
      },
      {
        'label': 'History',
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
                            arguments: {'userId': widget.userId, 'userName': widget.userName, 'userEmail': widget.userEmail},
                          );
                        }
                        if (action['label'] == 'Search Service') {
                          Navigator.pushNamed(
                            context,
                            'search-services',
                            arguments: {'userId': widget.userId},
                          );
                        }
                        if (action['label'] == 'Emergency/Towing') {
                          // _handleChatNavigation('emergency');
                        }
                        if (action['label'] == 'History') {
                          // _handleChatNavigation('history');
                        }
                        if (action['label'] == 'My Vehicle') {
                          // _handleChatNavigation('vehicle');
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
      final channel = await _chatService.createAdminSupportChannel(
        customerId: widget.userId,
        customerName: widget.userName ?? 'user',
      );

      if (channel != null) {
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
          title: 'Outstanding Payment',
          icon: Icons.account_balance_wallet,
          color: Colors.red,
          content: _buildPaymentContent(),
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          title: 'Latest Review',
          icon: Icons.star,
          color: Colors.amber,
          content: _buildReviewContent(),
        ),
        const SizedBox(height: 12),
        _buildStatusCard(
          title: 'Support Chat',
          icon: Icons.chat,
          color: Colors.blue,
          content: _buildChatContent(),
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
        _buildInfoRow('Status', apptStatus!),
        if (apptDateStr != null) _buildInfoRow('Date', apptDateStr!),
        if (apptCenterName != null) _buildInfoRow('Workshop', apptCenterName!),
      ],
    );
  }

  Widget _buildPaymentContent() {
    if (paymentAmount == null) {
      return const Text(
        'No outstanding payments',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Amount', 'RM ${paymentAmount!.toStringAsFixed(2)}'),
        if (paymentStatus != null) _buildInfoRow('Status', paymentStatus!),
        if (paymentDueStr != null) _buildInfoRow('Due Date', paymentDueStr!),
      ],
    );
  }

  Widget _buildReviewContent() {
    if (reviewRating == null && reviewComment == null) {
      return const Text(
        'No reviews yet',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reviewRating != null)
          _buildInfoRow('Rating', _buildStarRating(reviewRating!)),
        if (reviewComment != null) _buildInfoRow('Comment', '"$reviewComment"'),
        if (reviewCenterName != null)
          _buildInfoRow('Workshop', reviewCenterName!),
      ],
    );
  }

  Widget _buildChatContent() {
    if (lastMessageText == null) {
      return const Text(
        'No messages yet',
        style: TextStyle(color: Colors.grey, fontSize: 14),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          lastMessageText!,
          style: const TextStyle(fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (lastMessageTimeStr != null) ...[
          const SizedBox(height: 4),
          Text(
            lastMessageTimeStr!,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ],
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

  Widget _buildStarRating(double rating) {
    return Row(
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return const Icon(Icons.star, size: 16, color: Colors.amber);
        } else if (index < rating) {
          return const Icon(Icons.star_half, size: 16, color: Colors.amber);
        } else {
          return const Icon(Icons.star_border, size: 16, color: Colors.amber);
        }
      }),
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
              builder: (context) => const MessageChatListPage(),
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
