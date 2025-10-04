import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:automate_application/pages/chat/customer_support_chat_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:stream_chat_flutter/stream_chat_flutter.dart' as stream_chat;
import 'package:automate_application/pages/chat/service_center_chat_page.dart';
import 'package:automate_application/model/service_center_model.dart';
import 'package:automate_application/services/chat_service.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color infoColor = Color(0xFF3B82F6);
}

class MessageChatListPage extends StatefulWidget {
  final String userId;
  const MessageChatListPage({super.key, required this.userId});

  @override
  State<MessageChatListPage> createState() => _MessageChatListPageState();
}

class _MessageChatListPageState extends State<MessageChatListPage>
    with TickerProviderStateMixin {
  late final stream_chat.StreamChannelListController _channelListController;
  late TabController _tabController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  final Map<String, ServiceCenter> _serviceCenters = {};
  final Map<String, bool> _serviceCenterOnlineStatus = {};
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _setupChannelListController();
    _searchController.addListener(_onSearchChanged);
    _loadServiceCenters();
    _startOnlineStatusMonitoring();
  }

  void _setupChannelListController() {
    _channelListController = stream_chat.StreamChannelListController(
      client: stream_chat.StreamChat.of(context).client,
      filter: stream_chat.Filter.and([
        stream_chat.Filter.equal('type', 'messaging'),
        stream_chat.Filter.in_('members', [
          stream_chat.StreamChat.of(context).currentUser!.id,
        ]),
      ]),
      channelStateSort: [
        const stream_chat.SortOption('last_message_at', direction: stream_chat.SortOption.DESC),
      ],
    );
    _channelListController.doInitialLoad();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _loadServiceCenters() async {
    try {
      final querySnapshot = await firestore.FirebaseFirestore.instance
          .collection('service_centers')
          .get();

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final serviceCenter = ServiceCenter(
          id: doc.id,
          name: data['serviceCenterName']?.toString() ?? 'Unknown',
          email: data['email']?.toString() ?? 'N/A',
          serviceCenterPhoneNo: data['serviceCenterPhoneNo']?.toString() ?? '',
          addressLine1: data['addressLine1']?.toString() ?? 'Unknown location',
          rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
          isOnline: false,
          responseTime: data['responseTime']?.toString() ?? 'Within 24 hours',
          serviceCenterPhoto: data['serviceCenterPhoto']?.toString() ?? '',
          description: data['description']?.toString() ?? '',
          images: List<String>.from(data['images'] ?? []),
          postalCode: data['postalCode']?.toString() ?? '',
          city: data['city']?.toString() ?? '',
          state: data['state']?.toString() ?? '',
          latitude: (data['latitude'] as num?)?.toDouble(),
          longitude: (data['longitude'] as num?)?.toDouble(),
          reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
          specialClosures: _convertToMapList(data['specialClosures']),
          operatingHours: _convertToMapList(data['operatingHours']),
          verificationStatus: data['verificationStatus']?.toString() ?? '',
          updatedAt: DateTime.now(),
        );
        _serviceCenters[doc.id] = serviceCenter;
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading service centers: $e');
    }
  }

  List<Map<String, dynamic>> _convertToMapList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  void _startOnlineStatusMonitoring() {
    _enhanceOnlineStatusMonitoring(
        stream_chat.StreamChat.of(context).client,
        _serviceCenterOnlineStatus
    );
  }

  void _enhanceOnlineStatusMonitoring(stream_chat.StreamChatClient client, Map<String, bool> onlineStatus) {
    client.queryUsers(
      filter: stream_chat.Filter.in_('role', ['service_center']),
    ).then((users) {
      for (final user in users.users) {
        onlineStatus[user.id] = user.online;
      }
      if (mounted) setState(() {});
    });

    client.on(stream_chat.EventType.userUpdated).listen((event) {
      if (event.user?.role == 'service_center') {
        onlineStatus[event.user!.id] = event.user!.online ?? false;
        if (mounted) setState(() {});
      }
    });
  }

  ServiceCenter? _getServiceCenterFromChannel(stream_chat.Channel channel) {
    try {
      final centerInfo = channel.extraData['center_info'] as Map<String, dynamic>?;
      if (centerInfo != null) {
        final centerId = centerInfo['id'] as String?;
        if (centerId != null) {
          return _serviceCenters[centerId];
        }
      }

      // Fallback: try to extract service center ID from channel ID
      final channelId = channel.id;
      if (channelId != null && channelId.startsWith('service_center_')) {
        final parts = channelId.split('_');
        if (parts.length >= 3) {
          final centerId = parts[2];
          return _serviceCenters[centerId];
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting service center from channel: $e');
      return null;
    }
  }

  bool _isServiceCenterOnline(String centerId) {
    return _serviceCenterOnlineStatus[centerId] ?? false;
  }

  @override
  void dispose() {
    _channelListController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(),
        ],
        body: Column(
          children: [
            if (_isSearching) _buildSearchBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCustomerSupportTab(),
                  _buildServiceCentersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.cardColor,
      elevation: 0,
      floating: true,
      pinned: true,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.arrow_back_ios,
            color: AppColors.secondaryColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          _isSearching ? 'Search Messages' : 'Messages',
          key: ValueKey(_isSearching),
          style: const TextStyle(
            color: AppColors.secondaryColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isSearching
                  ? AppColors.primaryColor.withOpacity(0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: _isSearching ? AppColors.primaryColor : AppColors.secondaryColor,
              size: 20,
            ),
          ),
          onPressed: () {
            setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _searchController.clear();
                _searchQuery = '';
              }
            });
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search messages...',
            prefixIcon: Icon(Icons.search, color: Colors.grey),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primaryColor,
        unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: AppColors.primaryColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Customer Support'),
          Tab(text: 'Service Centers'),
        ],
      ),
    );
  }

  Widget _buildCustomerSupportTab() {
    return stream_chat.StreamChannelListView(
      controller: _channelListController,
      itemBuilder: (context, channels, index, tile) {
        final channel = channels[index];
        final customType = channel.extraData['custom_type'] as String?;

        // Filter for admin-support channels
        if (customType == 'admin-support') {
          return _CustomerSupportTile(channel: channel);
        }
        return const SizedBox.shrink();
      },
      emptyBuilder: (context) => _buildEmptyCustomerSupport(),
      loadingBuilder: (context) => _buildLoadingState(),
      errorBuilder: (context, error) => _buildErrorState(error),
    );
  }

  Widget _buildServiceCentersTab() {
    return stream_chat.StreamChannelListView(
      controller: _channelListController,
      itemBuilder: (context, channels, index, tile) {
        final channel = channels[index];
        final customType = channel.extraData['custom_type'] as String?;

        // Filter for service-center channels
        if (customType == 'service-center') {
          final serviceCenter = _getServiceCenterFromChannel(channel);
          final isOnline = serviceCenter != null
              ? _isServiceCenterOnline(serviceCenter.id)
              : false;

          return ServiceCenterChatTile(
            channel: channel,
            serviceCenter: serviceCenter,
            isOnline: isOnline,
          );
        }
        return const SizedBox.shrink();
      },
      emptyBuilder: (context) => _buildEmptyServiceCenters(),
      loadingBuilder: (context) => _buildLoadingState(),
      errorBuilder: (context, error) => _buildErrorState(error),
    );
  }

  Widget _buildEmptyServiceCenters() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.successColor.withOpacity(0.1),
                    AppColors.successColor.withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.car_repair,
                size: 64,
                color: AppColors.successColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Service Center Chats',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start chatting with service centers\nfrom their details page',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCustomerSupport() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor.withOpacity(0.1),
                    AppColors.primaryColor.withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.headset_mic,
                size: 64,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Need Help?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start a conversation with our customer\nsupport team for immediate assistance',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startCustomerSupportChat,
              icon: const Icon(Icons.chat_bubble),
              label: const Text('Start Support Chat'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primaryColor),
          SizedBox(height: 16),
          Text(
            'Loading messages...',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.errorColor,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unable to load messages',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _channelListController.doInitialLoad(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startCustomerSupportChat() async {
    try {
      final currentUser = stream_chat.StreamChat.of(context).currentUser;
      if (currentUser == null) return;

      // Use your ChatService to create the support channel
      final channel = await _chatService.createAdminSupportChannel(
        customerId: currentUser.id,
        customerName: currentUser.name ?? 'Customer',
        customerEmail: currentUser.extraData['email']?.toString(),
      );

      if (channel != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CustomerSupportChatPage(channel: channel),
          ),
        );
      } else {
        throw Exception('Failed to create support channel');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat: $e'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }
}

class ServiceCenterChatTile extends StatelessWidget {
  final stream_chat.Channel channel;
  final ServiceCenter? serviceCenter;
  final bool isOnline;

  const ServiceCenterChatTile({
    Key? key,
    required this.channel,
    required this.serviceCenter,
    required this.isOnline,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<stream_chat.Message>>(
      stream: channel.state?.messagesStream,
      initialData: channel.state?.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        final lastMessage = messages.isNotEmpty ? messages.last : null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ServiceCenterChatPage(
                    serviceCenterId: serviceCenter?.id ?? '',
                    serviceCenterName: serviceCenter?.name ?? 'Service Center',
                    channel: channel,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Service Center Avatar - FIXED VERSION
                  _buildServiceCenterAvatar(),
                  const SizedBox(width: 16),

                  // Service Center Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    serviceCenter?.name ?? 'Service Center',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondaryColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOnline ? AppColors.successColor : Colors.grey,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isOnline ? 'ONLINE' : 'OFFLINE',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastMessage?.text ?? 'Start a conversation',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        if (serviceCenter?.rating != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.star,
                                color: AppColors.warningColor,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                serviceCenter!.rating!.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${serviceCenter?.reviewCount ?? 0} reviews)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Time and Unread Count
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastMessage != null)
                        Text(
                          _formatTime(lastMessage.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      StreamBuilder<int>(
                        stream: channel.state?.unreadCountStream,
                        initialData: channel.state?.unreadCount ?? 0,
                        builder: (context, snapshot) {
                          final unreadCount = snapshot.data ?? 0;
                          if (unreadCount > 0) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceCenterAvatar() {
    final photoUrl = serviceCenter?.serviceCenterPhoto;

    if (photoUrl == null || photoUrl.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.car_repair,
          color: Colors.white,
          size: 24,
        ),
      );
    }

    // Handle different image types
    if (photoUrl.startsWith('data:image')) {
      // Base64 image
      try {
        final base64Str = photoUrl.split(',').last;
        final bytes = base64.decode(base64Str);
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        debugPrint('Error decoding base64 image: $e');
        return _buildDefaultAvatar();
      }
    } else if (photoUrl.startsWith('http')) {
      // Network image
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: NetworkImage(photoUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: photoUrl.isEmpty ? _buildDefaultAvatar() : null,
      );
    } else {
      return _buildDefaultAvatar();
    }
  }

  Widget _buildDefaultAvatar() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.car_repair,
        color: Colors.white,
        size: 24,
      ),
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class _CustomerSupportTile extends StatelessWidget {
  const _CustomerSupportTile({required this.channel});

  final stream_chat.Channel channel;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<stream_chat.Message>>(
      stream: channel.state?.messagesStream,
      initialData: channel.state?.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        final lastMessage = messages.isNotEmpty ? messages.first : null;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CustomerSupportChatPage(
                    channel: channel,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryColor, AppColors.primaryColor.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.transparent,
                      child: Icon(
                        Icons.headset_mic,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: const Text(
                                'Customer Support',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.successColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'ONLINE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastMessage?.text ?? 'How can we help you today?',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastMessage != null)
                        Text(
                          _formatTime(lastMessage.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      StreamBuilder<int>(
                        stream: channel.state?.unreadCountStream,
                        initialData: channel.state?.unreadCount ?? 0,
                        builder: (context, snapshot) {
                          final unreadCount = snapshot.data ?? 0;
                          if (unreadCount > 0) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return weekdays[dateTime.weekday - 1];
      } else {
        return '${dateTime.day}/${dateTime.month}';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}