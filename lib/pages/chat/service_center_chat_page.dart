import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart' as stream_chat;
import 'package:automate_application/services/chat_service.dart';

class ServiceCenterChatPage extends StatefulWidget {
  final String serviceCenterId;
  final String serviceCenterName;
  final stream_chat.Channel? channel;
  final String? serviceCenterAvatar;

  const ServiceCenterChatPage({
    Key? key,
    required this.serviceCenterId,
    required this.serviceCenterName,
    this.channel,
    this.serviceCenterAvatar,
  }) : super(key: key);

  @override
  State<ServiceCenterChatPage> createState() => _ServiceCenterChatPageState();
}

class _ServiceCenterChatPageState extends State<ServiceCenterChatPage> {
  late stream_chat.Channel _channel;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    if (widget.channel != null) {
      _channel = widget.channel!;
      _isLoading = false;
    } else {
      _initializeChat();
    }
  }

  Future<void> _initializeChat() async {
    try {
      final currentUser = stream_chat.StreamChat.of(context).currentUser;
      if (currentUser == null) {
        throw Exception('User not connected to chat');
      }

      final channel = await _chatService.createServiceCenterChannel(
        customerId: currentUser.id,
        centerId: widget.serviceCenterId,
        customerName: currentUser.name ?? 'Customer',
        centerName: widget.serviceCenterName,
        centerAvatar: widget.serviceCenterAvatar,
        customerAvatar: currentUser.extraData['avatar']?.toString(),
      );

      if (channel == null) {
        throw Exception('Failed to create service center channel');
      }

      setState(() {
        _channel = channel;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.serviceCenterName),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.serviceCenterName),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to load chat',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeChat,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return stream_chat.StreamChannel(
      channel: _channel,
      child: Scaffold(
        appBar: _buildCustomAppBar(),
        // appBar: stream_chat.StreamChannelHeader(),
        body: Column(
          children: [
            Expanded(
              child: stream_chat.StreamMessageListView(),
            ),
            stream_chat.StreamMessageInput(),
          ],
        ),
      ),
    );
  }

  AppBar _buildCustomAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Service Center Name
                Text(
                  widget.serviceCenterName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Online Status
                FutureBuilder<stream_chat.User?>(
                  future: _getServiceCenterUser(),
                  builder: (context, snapshot) {
                    final isOnline = snapshot.data?.online ?? false;
                    return Text(
                      isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildServiceCenterAvatar(),
        ],
      ),
      backgroundColor: Colors.white,
      elevation: 1,
      iconTheme: const IconThemeData(color: Colors.black),
      titleTextStyle: const TextStyle(color: Colors.black),
    );
  }

  // Build service center avatar for the app bar
  Widget _buildServiceCenterAvatar() {
    // Use the passed serviceCenterAvatar first
    if (widget.serviceCenterAvatar != null && widget.serviceCenterAvatar!.isNotEmpty) {
      if (widget.serviceCenterAvatar!.startsWith('http')) {
        // Network image
        return CircleAvatar(
          backgroundImage: NetworkImage(widget.serviceCenterAvatar!),
          radius: 20,
        );
      } else if (widget.serviceCenterAvatar!.startsWith('data:image')) {
        // Base64 image
        try {
          final base64Str = widget.serviceCenterAvatar!.split(',').last;
          final bytes = base64.decode(base64Str);
          return CircleAvatar(
            backgroundImage: MemoryImage(bytes),
            radius: 20,
          );
        } catch (e) {
          debugPrint('Error decoding base64 avatar: $e');
          return _buildDefaultAvatar();
        }
      }
    }

    // Fallback to channel image
    final channelImage = _channel.image ?? _channel.extraData['image'] as String?;
    if (channelImage != null && channelImage.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(channelImage),
        radius: 20,
      );
    }

    // Final fallback to default avatar
    return _buildDefaultAvatar();
  }

  // Default avatar widget
  Widget _buildDefaultAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.car_repair,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  // Get service center user for online status
  Future<stream_chat.User?> _getServiceCenterUser() async {
    try {
      final client = stream_chat.StreamChat.of(context).client;
      final usersResult = await client.queryUsers(
        filter: stream_chat.Filter.equal('id', widget.serviceCenterId),
      );
      return usersResult.users.isNotEmpty ? usersResult.users.first : null;
    } catch (e) {
      return null;
    }
  }
}