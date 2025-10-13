import 'package:flutter/material.dart' hide Key;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/pages/chat/service_center_chat_page.dart';
import 'package:automate_application/services/chat_service.dart';
import 'package:automate_application/model/review_model.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

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
  List<Review> _reviews = [];
  bool _loadingReviews = true;
  double _currentRating = 0.0;
  int _currentReviewCount = 0;
  Map<int, int> _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _currentRating = widget.center.rating;
    _currentReviewCount = widget.center.reviewCount;

    // Initialize chat when the sheet opens
    _initializeChat();
    _loadReviews();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    if (_isInitializingChat || _chatInitialized) return;

    setState(() => _isInitializingChat = true);

    try {
      await _chatService.initialize('3mj9hufw92nk');

      setState(() => _chatInitialized = true);

    } catch (e) {
      debugPrint('Chat initialization error: $e');
    } finally {
      setState(() => _isInitializingChat = false);
    }
  }

  void _navigateToServiceCenterChat() async {
    setState(() => _isInitializingChat = true);

    try {
      final client = StreamChat.of(context).client;
      final channelId = 'service_center_${widget.center.id}_${widget.userId}';

      final channel = client.channel('messaging', id: channelId, extraData: {
        'name': '${widget.center.name} - Support',
        'members': [widget.userId, widget.center.id],
        'custom_type': 'service-center',
        'created_by_id': widget.userId,
        'image': 'https://i.imgur.com/fR9Jz14.png',
        'customer_info': {
          'id': widget.userId,
          'name': widget.userName ?? 'User',
        },
        'center_info': {
          'id': widget.center.id,
          'name': widget.center.name,
        },
      });

      await channel.watch();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ServiceCenterChatPage(
              serviceCenterId: widget.center.id,
              serviceCenterName: widget.center.name,
              channel: channel,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in direct chat setup: $e');
      _showChatNotAvailable();
    } finally {
      if (mounted) {
        setState(() => _isInitializingChat = false);
      }
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

  Future<void> _loadReviews() async {
    try {
      setState(() => _loadingReviews = true);
      _reviews = [];

      // Load reviews from the dedicated reviews collection
      final reviewsQuery =
          await FirebaseFirestore.instance
              .collection('reviews')
              .where('serviceCenterId', isEqualTo: widget.center.id)
              .where('status', isEqualTo: 'approved')
              .get();

      // Process reviews
      for (var doc in reviewsQuery.docs) {
        try {
          final data = doc.data();

          Map<String, dynamic> vehicleInfo = {};
          try {
            if (data['vehicleInfo'] != null) {
              if (data['vehicleInfo'] is Map<String, dynamic>) {
                vehicleInfo = data['vehicleInfo'] as Map<String, dynamic>;
              } else if (data['vehicleInfo'] is Map) {
                vehicleInfo = Map<String, dynamic>.from(
                  data['vehicleInfo'] as Map,
                );
              }
            }
          } catch (e) {
            debugPrint('Error parsing vehicleInfo: $e');
            vehicleInfo = {};
          }

          // Extract services safely
          List<dynamic> services = [];
          try {
            if (data['services'] != null && data['services'] is List) {
              services = data['services'] as List<dynamic>;
            }
          } catch (e) {
            debugPrint('Error parsing services: $e');
            services = [];
          }

          DateTime reviewedAt;
          try {
            reviewedAt =
                (data['reviewedAt'] as Timestamp?)?.toDate() ??
                (data['createdAt'] as Timestamp?)?.toDate() ??
                DateTime.now();
          } catch (e) {
            debugPrint('Error parsing reviewedAt: $e');
            reviewedAt = DateTime.now();
          }

          DateTime createdAt;
          try {
            createdAt =
                (data['createdAt'] as Timestamp?)?.toDate() ??
                (data['reviewedAt'] as Timestamp?)?.toDate() ??
                DateTime.now();
          } catch (e) {
            debugPrint('Error parsing createdAt: $e');
            createdAt = DateTime.now();
          }

          final review = Review(
            id: doc.id,
            serviceCenterId:
                data['serviceCenterId']?.toString() ?? widget.center.id,
            serviceCenterName:
                data['serviceCenterName']?.toString() ?? widget.center.name,
            userId: data['userId']?.toString() ?? '',
            userName: data['userName']?.toString() ?? 'Anonymous',
            userEmail: data['userEmail']?.toString() ?? '',
            type: data['type']?.toString() ?? 'service',
            rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
            comment: data['comment']?.toString(),
            reviewedAt: reviewedAt,
            createdAt: createdAt,
            totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
            vehicleInfo: vehicleInfo,
            towingType: data['towingType']?.toString(),
            services: services,
            packages: data['packages'] as List<dynamic>?,
            selectionType: data['selectionType']?.toString(),
            bookingId: data['bookingId']?.toString() ?? '',
            status: data['status']?.toString() ?? 'approved',
          );
          _reviews.add(review);

          debugPrint(
            'Successfully added review: ${review.userName} - ${review.rating} stars',
          );
        } catch (e, stackTrace) {
          debugPrint('Error processing review ${doc.id}: $e');
          debugPrint('Stack trace: $stackTrace');
        }
      }

      // Calculate average rating and total reviews
      _calculateAverageRating();
      _calculateRatingDistribution();

      setState(() => _loadingReviews = false);
    } catch (e, stackTrace) {
      debugPrint('Error loading reviews: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() => _loadingReviews = false);
    }
  }

  void _calculateAverageRating() {
    if (_reviews.isEmpty) {
      _currentRating = 0.0;
      _currentReviewCount = 0;
      return;
    }

    try {
      double totalRating = 0.0;
      int validReviews = 0;

      for (var review in _reviews) {
        if (review.rating >= 1 && review.rating <= 5) {
          totalRating += review.rating;
          validReviews++;
        }
      }

      if (validReviews > 0) {
        _currentRating = totalRating / validReviews;
        _currentReviewCount = validReviews;
      } else {
        _currentRating = 0.0;
        _currentReviewCount = 0;
      }
    } catch (e) {
      debugPrint('Error calculating average rating: $e');
      _currentRating = 0.0;
      _currentReviewCount = 0;
    }
  }

  void _calculateRatingDistribution() {
    _ratingDistribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

    if (_reviews.isNotEmpty) {
      for (var review in _reviews) {
        try {
          final ratingKey = review.rating.floor();
          if (ratingKey >= 1 && ratingKey <= 5) {
            _ratingDistribution[ratingKey] =
                (_ratingDistribution[ratingKey] ?? 0) + 1;
          }
        } catch (e) {
          debugPrint('Error processing rating for distribution: $e');
        }
      }
    }
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

  Widget _buildStarRating(double rating, {double size = 18}) {
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

  Widget _buildPackagesSection() {
    if (widget.center.packages.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildInfoSection(
      title: 'Service Packages',
      icon: Icons.inventory_2_rounded,
      children: [
        Column(
          children:
              widget.center.packages.map((package) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Package name and price
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              package.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Package description
                      if (package.description.isNotEmpty)
                        Column(
                          children: [
                            Text(
                              package.description,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                height: 1.4,
                              ),
                              maxLines: 10,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),

                      if (package.services.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                              'Services included:',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children:
                                  package.services.map((service) {
                                    // Extract service name from PackageService object
                                    String serviceName = _extractServiceName(
                                      service,
                                    );
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentColor
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.accentColor
                                              .withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        serviceName,
                                        style: TextStyle(
                                          color: AppColors.accentColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  String _extractServiceName(dynamic service) {
    if (service is String) {
      return service;
    } else if (service is Map<String, dynamic>) {
      return service['name'] ?? service['serviceName'] ?? 'Service';
    } else {
      try {
        final dynamic serviceObj = service;
        return serviceObj.serviceName?.toString() ?? 'Service';
      } catch (e) {
        debugPrint('Error extracting service name: $e');
        return 'Service';
      }
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
                        _buildStarRating(_currentRating),
                        const SizedBox(width: 8),
                        Text(
                          '${_currentRating.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          ' ($_currentReviewCount reviews)',
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
                _buildPackagesSection(),
                const SizedBox(height: 24),
                _buildReviewsSection(),

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

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              border: Border(top: BorderSide(color: AppColors.borderColor)),
            ),
            child: Column(
              children: [
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
                        icon:
                            _isInitializingChat
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
                          foregroundColor:
                              _chatInitialized
                                  ? Colors.green
                                  : (_isInitializingChat
                                      ? Colors.grey
                                      : AppColors.accentColor),
                          side: BorderSide(
                            color:
                                _chatInitialized
                                    ? Colors.green
                                    : (_isInitializingChat
                                        ? Colors.grey
                                        : AppColors.accentColor),
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

  Widget _buildReviewsSection() {
    return _buildInfoSection(
      title: 'Customer Reviews',
      icon: Icons.reviews_rounded,
      children: [
        // Rating Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: Column(
            children: [
              // Overall Rating
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      Text(
                        _currentRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      _buildStarRating(
                        _currentRating,
                        size: 20,
                      ),
                      Text(
                        '$_currentReviewCount reviews',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  // Rating Distribution
                  Expanded(
                    child: Column(
                      children:
                          [5, 4, 3, 2, 1].map((rating) {
                            final count = _ratingDistribution[rating] ?? 0;
                            final percentage =
                                _reviews.isNotEmpty
                                    ? (count / _reviews.length) * 100
                                    : 0;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Text(
                                    '$rating',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.star,
                                    color: Colors.amber,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: percentage / 100,
                                      backgroundColor: AppColors.borderColor,
                                      color: Colors.amber,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Reviews List
        if (_loadingReviews)
          const Center(
            child: CircularProgressIndicator(color: AppColors.primaryColor),
          )
        else if (_reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.reviews_outlined,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                Text(
                  'No Reviews Yet',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Be the first to review this service center!',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Column(
            children:
                _reviews
                    .take(5)
                    .map((review) => _buildReviewCard(review))
                    .toList(),
          ),

        // View All Reviews Button
        if (_reviews.length > 5)
          Container(
            margin: const EdgeInsets.only(top: 16),
            child: OutlinedButton(
              onPressed: _showAllReviews,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryColor,
                side: BorderSide(color: AppColors.primaryColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: Text('View All ${_reviews.length} Reviews'),
            ),
          ),
      ],
    );
  }

  String _maskName(String name) {
    if (name.isEmpty) return 'Anonymous';
    if (name.length <= 3) return name;
    return '${name.substring(0, 3)}***';
  }

  String _maskEmail(String email) {
    if (email.isEmpty) return '***';

    final atIndex = email.indexOf('@');
    if (atIndex == -1) {
      // If no @ found, just show first 3 characters
      return email.length <= 3 ? email : '${email.substring(0, 3)}***';
    }

    final username = email.substring(0, atIndex);
    final domain = email.substring(atIndex);

    if (username.length <= 3) {
      return '${username}***$domain';
    } else {
      return '${username.substring(0, 3)}***$domain';
    }
  }

  Widget _buildReviewCard(Review review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with User Info and Rating
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maskName(review.userName),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskEmail(review.userEmail),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStarRating(review.rating, size: 16),
            ],
          ),

          const SizedBox(height: 12),

          // Review Comment
          if (review.comment != null && review.comment!.isNotEmpty)
            Column(
              children: [
                Text(
                  review.comment!,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),

          // Service Details show actual services used
          if (review.services != null && review.services!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Services Used:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...review.services!.take(3).map((service) {
                    final serviceName = _extractServiceNameFromReview(service);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '• $serviceName',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                  if (review.services!.length > 3)
                    Text(
                      '+ ${review.services!.length - 3} more services',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Vehicle Information
          if (review.vehicleInfo.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_car_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatVehicleInfo(review.vehicleInfo),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Footer with Date and Amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('dd MMM yyyy').format(review.reviewedAt),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _extractServiceNameFromReview(dynamic service) {
    if (service is String) {
      return service;
    } else if (service is Map<String, dynamic>) {
      return service['serviceName'] ?? service['name'] ?? 'Service';
    } else {
      return 'Service';
    }
  }

  String _formatVehicleInfo(Map<String, dynamic> vehicleInfo) {
    final make = vehicleInfo['make'] ?? '';
    final model = vehicleInfo['model'] ?? '';
    final year = vehicleInfo['year']?.toString() ?? '';

    List<String> parts = [];
    if (make.isNotEmpty) parts.add(make);
    if (model.isNotEmpty) parts.add(model);
    if (year.isNotEmpty) parts.add(year);

    return parts.join(' • ');
  }

  void _showAllReviews() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            height: MediaQuery.of(context).size.height * 0.8,
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
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'All Reviews (${_reviews.length})', // Use actual reviews count
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),

                // Reviews List
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children:
                        _reviews
                            .map((review) => _buildReviewCard(review))
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
