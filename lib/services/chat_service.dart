import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  late StreamChatClient _client;
  final String _baseUrl = 'http://192.168.0.141:3000'; // take from laptop ipv4 address

  factory ChatService() => _instance;

  ChatService._internal();

  StreamChatClient get client => _client;

  Future<bool> initialize(String apiKey) async {
    try {
      _client = StreamChatClient(apiKey);
      return true;
    } catch (e) {
      debugPrint('Chat service initialization error: $e');
      return false;
    }
  }

  // Connect user with server-side token
  Future<Map<String, dynamic>> connectUser({
    required String userId,
    required String name,
    String? email,
    String role = 'user',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'name': name,
          'email': email,
          'role': role,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to get token: ${response.body}');
      }

      final data = json.decode(response.body);

      final streamUser = User(
        id: userId,
        name: name,
        image: 'https://i.imgur.com/fR9Jz14.png',
        extraData: {
          'email': email ?? '',
          'role': role,
        },
      );

      await _client.connectUser(streamUser, data['token']);
      return {'success': true, 'user': data};
    } catch (e) {
      debugPrint('Connect user error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Create support channel
  Future<Channel?> createAdminSupportChannel({
    required String customerId,
    required String customerName,
    String? customerEmail,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/channels/admin-support'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerId': customerId,
          'customerName': customerName,
          'customerEmail': customerEmail,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create support channel: ${response.body}');
      }

      final data = json.decode(response.body);
      final channel = _client.channel(data['channel_type'], id: data['channel_id']);
      await channel.watch();
      return channel;
    } catch (e) {
      debugPrint('Create support channel error: $e');
      return null;
    }
  }

  // Create service center channel
  Future<Channel?> createServiceCenterChannel({
    required String customerId,
    required String centerId,
    required String customerName,
    required String centerName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/channels/service-center'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerId': customerId,
          'customerName': customerName,
          'centerId': centerId,
          'centerName': centerName,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create service channel: ${response.body}');
      }

      final data = json.decode(response.body);
      final channelId = data['channel_id'];

      // get the channel that created by the server
      final channel = _client.channel('messaging', id: channelId);
      await channel.watch();

      return channel;
    } catch (e) {
      debugPrint('Create service channel error: $e');
      return null;
    }
  }

  Future<void> disconnect() async {
    try {
      await _client.disconnectUser();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }
}