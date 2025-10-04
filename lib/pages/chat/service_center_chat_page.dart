import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart' as stream_chat;
import 'package:automate_application/services/chat_service.dart';

class ServiceCenterChatPage extends StatefulWidget {
  final String serviceCenterId;
  final String serviceCenterName;
  final stream_chat.Channel? channel;

  const ServiceCenterChatPage({
    Key? key,
    required this.serviceCenterId,
    required this.serviceCenterName,
    this.channel,
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
        appBar: stream_chat.StreamChannelHeader(),
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
}