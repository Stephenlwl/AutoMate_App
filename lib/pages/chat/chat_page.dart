import 'package:flutter/material.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:flutter/services.dart';

class AppColors {
  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF1F2A44);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color cardColor = Colors.white;
  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);
}

class ChatPage extends StatefulWidget {
  final String userId;
  final Channel channel;

  const ChatPage({
    super.key,
    required this.userId,
    required this.channel,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final StreamMessageInputController _controller = StreamMessageInputController();
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isTyping = false;
  bool _isSending = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _watchChannel();
    _setupAnimations();
    _textController.addListener(_onTextChanged);
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _isTyping) {
      setState(() {
        _isTyping = hasText;
      });
    }
  }

  Future<void> _watchChannel() async {
    try {
      await widget.channel.watch();
    } catch (e) {
      debugPrint('Error watching channel: $e');
      _showErrorSnackBar('Failed to connect to chat');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamChannel(
      channel: widget.channel,
      child: Scaffold(
        backgroundColor: AppColors.backgroundColor,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(
              child: StreamMessageListView(
                messageBuilder: (context, details, messages, defaultMessage) {
                  final msgs = messages.cast<Message>();
                  final idx = msgs.indexWhere((m) => m.id == details.message.id);
                  final Message? nextMessage =
                  (idx != -1 && idx < msgs.length - 1) ? msgs[idx + 1] : null;

                  return _buildCustomMessage(details, nextMessage);
                },
                emptyBuilder: (context) => _buildEmptyState(),
                loadingBuilder: (context) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chat_bubble,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading messages...',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildCustomMessageInput(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.cardColor,
      elevation: 0,
      shadowColor: Colors.grey.withOpacity(0.1),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          child: const Icon(
            Icons.arrow_back_ios,
            color: AppColors.secondaryColor,
            size: 18,
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Hero(
            tag: 'channel_avatar_${widget.channel.id}',
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _getChannelColor(),
                    _getChannelColor().withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getChannelColor().withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.transparent,
                child: Icon(
                  _getChannelIcon(),
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.channel.extraData['name'] as String? ?? 'Customer Support',
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.successColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getChannelSubtitle(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.phone,
              color: AppColors.primaryColor,
              size: 20,
            ),
          ),
          onPressed: () {
            _showSnackBar('Voice call feature coming soon!', AppColors.warningColor);
          },
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            child: const Icon(
              Icons.videocam,
              color: AppColors.primaryColor,
              size: 20,
            ),
          ),
          onPressed: () {
            _showSnackBar('Video call feature coming soon!', AppColors.warningColor);
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryColor.withOpacity(0.1),
                        AppColors.primaryColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.support_agent,
                    size: 64,
                    color: AppColors.primaryColor,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Welcome to Customer Support',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.secondaryColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Start a conversation with our support team\nWe\'re here to help you',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomMessage(MessageDetails details, Message? nextMessage) {
    final message = details.message;
    final isCurrentUser = message.user?.id == StreamChat.of(context).currentUser?.id;
    final isNextMessageFromSameUser = nextMessage?.user?.id == message.user?.id;
    final showAvatar = !isCurrentUser && !isNextMessageFromSameUser;
    final hasAttachment = message.attachments.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isCurrentUser) ...[
            SizedBox(
              width: 36,
              child: showAvatar
                  ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _getChannelColor(),
                      _getChannelColor().withOpacity(0.8),
                    ],
                  ),
                ),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.transparent,
                  child: Icon(
                    _getChannelIcon(),
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              )
                  : const SizedBox(),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: isCurrentUser
                        ? LinearGradient(
                      colors: [AppColors.primaryColor, AppColors.primaryColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    color: isCurrentUser ? null : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: isCurrentUser
                            ? AppColors.primaryColor.withOpacity(0.3)
                            : Colors.grey.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasAttachment) _buildAttachmentPreview(message.attachments.first),
                      if (message.text?.isNotEmpty == true)
                        Text(
                          message.text ?? '',
                          style: TextStyle(
                            color: isCurrentUser
                                ? Colors.white
                                : AppColors.secondaryColor,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isNextMessageFromSameUser) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _formatTime(message.createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: showAvatar
                  ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryColor,
                      AppColors.primaryColor.withOpacity(0.8),
                    ],
                  ),
                ),
                child: const CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.secondaryColor,
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              )
                  : const SizedBox(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview(Attachment attachment) {
    switch (attachment.type) {
      case 'image':
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              attachment.imageUrl ?? '',
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 100,
                color: Colors.grey.shade200,
                child: const Center(child: Icon(Icons.error)),
              ),
            ),
          ),
        );
      case 'file':
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.attach_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attachment.title ?? 'File',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.add,
                  color: AppColors.primaryColor,
                  size: 22,
                ),
              ),
              onPressed: () => _showAttachmentOptions(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: _isTyping
                                ? LinearGradient(
                              colors: [AppColors.primaryColor, AppColors.primaryColor.withOpacity(0.8)],
                            )
                                : null,
                            color: _isTyping ? null : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: _isSending
                              ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _isTyping ? Colors.white : Colors.grey.shade600,
                              ),
                            ),
                          )
                              : Icon(
                            Icons.send,
                            color: _isTyping ? Colors.white : Colors.grey.shade600,
                            size: 16,
                          ),
                        ),
                        onPressed: _isSending ? null : _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      await widget.channel.sendMessage(
        Message(text: text),
      );

      // Clear the text field properly
      _textController.clear();
      _controller.clear();

      // Show success feedback
      HapticFeedback.lightImpact();

    } catch (e) {
      debugPrint('Error sending message: $e');
      _showErrorSnackBar('Failed to send message. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('MMM d, y').format(dateTime);
    } else if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
      } else {
        return DateFormat('EEE HH:mm').format(dateTime);
      }
    } else if (difference.inHours > 0) {
      return DateFormat('HH:mm').format(dateTime);
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Color _getChannelColor() {
    final channelType = widget.channel.extraData['type'] as String?;
    switch (channelType) {
      case 'admin-support':
        return const Color(0xFF3B82F6);
      case 'service-center':
        return AppColors.successColor;
      default:
        return AppColors.primaryColor;
    }
  }

  IconData _getChannelIcon() {
    final channelType = widget.channel.extraData['type'] as String?;
    switch (channelType) {
      case 'admin-support':
        return Icons.support_agent;
      case 'service-center':
        return Icons.home_repair_service;
      default:
        return Icons.chat_bubble;
    }
  }

  String _getChannelSubtitle() {
    final channelType = widget.channel.extraData['type'] as String?;
    switch (channelType) {
      case 'admin-support':
        return 'Customer Support Team';
      case 'service-center':
        return 'Service Center Support';
      default:
        return 'Online now';
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Send Attachment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo_camera,
                  label: 'Camera',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: AppColors.successColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.location_on,
                  label: 'Location',
                  color: AppColors.errorColor,
                  onTap: () {
                    Navigator.pop(context);
                    _shareLocation();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.attach_file,
                  label: 'File',
                  color: AppColors.warningColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.15),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // Camera and Gallery functionality
  Future<void> _pickImage(ImageSource source) async {
    try {
      final status = source == ImageSource.camera
          ? await Permission.camera.request()
          : await Permission.photos.request();

      if (!status.isGranted) {
        _showErrorSnackBar('Permission denied. Please enable ${source == ImageSource.camera ? 'camera' : 'photo'} access in settings.');
        return;
      }

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image != null) {
        await _sendImageMessage(File(image.path));
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      _showErrorSnackBar('Failed to pick image. Please try again.');
    }
  }

  Future<void> _sendImageMessage(File imageFile) async {
    try {
      setState(() {
        _isSending = true;
      });

      final message = Message(
        text: '',
        attachments: [
          Attachment(
            type: 'image',
            file: AttachmentFile(
              path: imageFile.path,
              size: await imageFile.length(),
            ),
          ),
        ],
      );

      await widget.channel.sendMessage(message);
      _showSnackBar('Image sent successfully!', AppColors.successColor);

    } catch (e) {
      debugPrint('Error sending image: $e');
      _showErrorSnackBar('Failed to send image. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // File picker functionality
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        await _sendFileMessage(file, result.files.single.name);
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      _showErrorSnackBar('Failed to pick file. Please try again.');
    }
  }

  Future<void> _sendFileMessage(File file, String fileName) async {
    try {
      setState(() {
        _isSending = true;
      });

      final message = Message(
        text: '',
        attachments: [
          Attachment(
            type: 'file',
            title: fileName,
            file: AttachmentFile(
              path: file.path,
              size: await file.length(),
            ),
          ),
        ],
      );

      await widget.channel.sendMessage(message);
      _showSnackBar('File sent successfully!', AppColors.successColor);

    } catch (e) {
      debugPrint('Error sending file: $e');
      _showErrorSnackBar('Failed to send file. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // Location sharing functionality
  Future<void> _shareLocation() async {
    try {
      final permission = await Permission.location.request();
      if (!permission.isGranted) {
        _showErrorSnackBar('Location permission denied. Please enable location access in settings.');
        return;
      }

      setState(() {
        _isSending = true;
      });

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final locationText = '📍 My Location \n\nView on Maps: https://maps.google.com/?q=${position.latitude},${position.longitude}';

      final message = Message(
        text: locationText,
        attachments: [
          Attachment(
            type: 'location',
            extraData: {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
          ),
        ],
      );

      setState(() {
        _isSending = false;
      });
      await widget.channel.sendMessage(message);
      _showSnackBar('Location shared successfully!', AppColors.successColor);

    } catch (e) {
      debugPrint('Error sharing location: $e');
      if (e.toString().contains('timeout')) {
        _showErrorSnackBar('Location request timed out. Please try again.');
      } else {
        _showErrorSnackBar('Failed to get location. Please check your GPS settings.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.successColor ? Icons.check_circle : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, AppColors.errorColor);
  }
}