import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  late StreamChatClient _client;
  final String _baseUrl = 'http://192.168.0.141:3000';

  factory ChatService() => _instance;

  ChatService._internal();

  StreamChatClient get client => _client;

  Future<bool> initialize(String apiKey) async {
    try {
      _client = StreamChatClient(
        apiKey,
        logLevel: Level.INFO,
      );
      return true;
    } catch (e) {
      debugPrint('Chat service initialization error: $e');
      return false;
    }
  }

  String _generateAvatarUrl(String name, {String type = 'user'}) {
    final colors = {
      'admin': '4A90E2',
      'service_center': 'FF6B00',
      'user': '8E44AD'
    };

    final color = colors[type] ?? colors['user']!;
    final encodedName = Uri.encodeComponent(name);
    return 'https://ui-avatars.com/api/?name=$encodedName&background=$color&color=fff&size=128&bold=true&length=2';
  }

  // Connect user directly to Stream Chat
  Future<Map<String, dynamic>> connectUser({
    required String userId,
    required String name,
    String? email,
    String? avatar,
    String role = 'user',
  }) async {
    try {
      String userAvatar;
      if (avatar != null && avatar.isNotEmpty) {
        userAvatar = avatar;
      } else {
        userAvatar = _generateAvatarUrl(name, type: role);
      }
      // use client-side token generation
      final streamUser = User(
        id: userId,
        name: name,
        role: role,
        image: userAvatar,
        extraData: {
          'email': email ?? '',
          'avatar': userAvatar,
        },
      );

      // Use development token
      final token = _client.devToken(userId).rawValue;

      await _client.connectUser(streamUser, token);

      return {
        'success': true,
        'user': streamUser.toJson(),
        'method': 'direct'
      };
    } catch (e) {
      debugPrint('Connect user error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Create support channel directly
  Future<Channel?> createAdminSupportChannel({
    required String customerId,
    required String customerName,
    String? customerEmail,
    String? customerAvatar,
  }) async {
    try {
      final serverReachable = await _isServerReachable();

      if (serverReachable) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/channels/admin-support'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'customerId': customerId,
              'customerName': customerName,
              'customerEmail': customerEmail,
              'customerAvatar': customerAvatar,
            }),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final channel = _client.channel(data['channel_type'], id: data['channel_id']);
            await channel.watch();
            return channel;
          }
        } catch (e) {
          debugPrint('Backend channel creation failed: $e');
        }
      }

      // Create channel directly
      return await _createAdminSupportChannelDirect(
        customerId: customerId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerAvatar: customerAvatar,
      );
    } catch (e) {
      debugPrint('Create support channel error: $e');
      return null;
    }
  }

  Future<Channel> _createAdminSupportChannelDirect({
    required String customerId,
    required String customerName,
    String? customerEmail,
    String? customerAvatar,
  }) async {
    final channelId = 'admin_support_$customerId';

    final adminAvatar = _generateAvatarUrl('AutoMate Support', type: 'admin');
    final userAvatar = customerAvatar ?? _generateAvatarUrl(customerName, type: 'user');

    final channel = _client.channel('messaging', id: channelId, extraData: {
      'name': 'Customer Support',
      'members': [customerId, 'admin-support'],
      'custom_type': 'admin-support',
      'created_by_id': customerId,
      'image': adminAvatar,
      'customer_info': {
        'id': customerId,
        'name': customerName,
        'email': customerEmail,
        'avatar': userAvatar,
      },
    });

    try {
      await channel.create();
      await channel.watch();
      return channel;
    } catch (e) {
      debugPrint('Direct channel creation error: $e');
      // try to query the channel first if fail
      try {
        await channel.watch();
        return channel;
      } catch (e2) {
        debugPrint('Channel watch also failed: $e2');
        rethrow;
      }
    }
  }

  // Create service center channel
  Future<Channel?> createServiceCenterChannel({
    required String customerId,
    required String centerId,
    required String customerName,
    required String centerName,
    String? customerAvatar,
    String? centerAvatar,
  }) async {
    try {
      final serverReachable = await _isServerReachable();

      if (serverReachable) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/channels/service-center'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'customerId': customerId,
              'customerName': customerName,
              'centerId': centerId,
              'centerName': centerName,
              'customerAvatar': customerAvatar,
              'centerAvatar': centerAvatar,
            }),
          ).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final channelId = data['channel_id'];
            final channel = _client.channel('messaging', id: channelId);
            await channel.watch();
            return channel;
          }
        } catch (e) {
          debugPrint('Backend service channel creation failed: $e');
        }
      }

      // Direct channel creation
      return await _createServiceCenterChannelDirect(
        customerId: customerId,
        centerId: centerId,
        customerName: customerName,
        centerName: centerName,
        customerAvatar: customerAvatar,
        centerAvatar: centerAvatar,
      );
    } catch (e) {
      debugPrint('Create service channel error: $e');
      return null;
    }
  }

  Future<Channel> _createServiceCenterChannelDirect({
    required String customerId,
    required String centerId,
    required String customerName,
    required String centerName,
    String? customerAvatar,
    String? centerAvatar,
  }) async {
    final channelId = 'service_center_${centerId}_${customerId}';
    final userAvatar = customerAvatar ?? _generateAvatarUrl(customerName, type: 'user');
    final serviceCenterAvatar = centerAvatar ?? _generateAvatarUrl(centerName, type: 'service_center');

    final channel = _client.channel('messaging', id: channelId, extraData: {
      'name': centerName,
      'members': [customerId, centerId],
      'custom_type': 'service-center',
      'created_by_id': customerId,
      'image': serviceCenterAvatar,
      'customer_info': {
        'id': customerId,
        'name': customerName,
        'avatar': userAvatar,
      },
      'center_info': {
        'id': centerId,
        'name': centerName,
        'avatar': serviceCenterAvatar,
      },
    });

    try {
      await channel.create();
      await channel.watch();
      return channel;
    } catch (e) {
      debugPrint('Direct service channel creation error: $e');
      try {
        await channel.watch();
        return channel;
      } catch (e2) {
        debugPrint('Service channel watch also failed: $e2');
        rethrow;
      }
    }
  }

  Future<void> updateUserAvatar({
    required String userId,
    required String avatarUrl,
  }) async {
    try {
      await _client.updateUser(
        User(
          id: userId,
          image: avatarUrl,
          extraData: {
            'avatar': avatarUrl,
          },
        ),
      );
    } catch (e) {
      debugPrint('Update user avatar error: $e');
    }
  }

  Future<bool> _isServerReachable() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Server not reachable: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      if (_client.state.currentUser != null) {
        await _client.disconnectUser();
      }
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }
}