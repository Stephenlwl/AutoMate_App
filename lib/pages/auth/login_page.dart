import 'package:flutter/material.dart';
import 'package:automate_application/widgets/custom_snackbar.dart';
import 'package:automate_application/utils/validators.dart';
import 'package:automate_application/services/auth_service.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color primaryColor = Color(0xFFFF6B00);
  static const Color secondaryColor = Color(0xFF344370);
  static const Color backgroundColor = Color(0xFFF8FAFC);
  static const Color surfaceColor = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      // Use AuthService for login
      final result = await _authService.loginCarOwner(
        email: email,
        password: password,
      );

      if (result.success) {
        final userId = result.userId ?? 'guest';
        final userName = result.userName;
        final userEmail = result.userEmail;

        await _connectUser(userId, userName ?? 'Guest', userEmail);

        if (mounted) {
          CustomSnackBar.show(
            context: context,
            message: 'Welcome back!',
            type: SnackBarType.success,
          );

          Navigator.pushReplacementNamed(
            context,
            '/home',
            arguments: {
              'userId': userId,
              'userName': userName,
              'userEmail': userEmail,
            },
          );
        }
      } else {
        if (mounted) {
          final msg = result.errorMessage ?? 'Login failed';

          // check pending account
          if (msg.contains('under review')) {
            Navigator.pushReplacementNamed(context, '/register/pending');
            CustomSnackBar.show(
              context: context,
              message:
                  'Your account is under review. Please wait for admin approval.',
              type: SnackBarType.warning,
            );
          } else {
            CustomSnackBar.show(
              context: context,
              message: msg,
              type: SnackBarType.error,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context: context,
          message: 'An unexpected error occurred: ${e.toString()}',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    // Navigate to forgot password page
    Navigator.pushNamed(context, '/forgot-password');
  }

  Future<void> _connectUser(
    String userId,
    String? userName,
    String? userEmail,
  ) async {
    try {
      final chatClient = StreamChat.of(context).client;

      // Check if user is already connected
      final currentUser = chatClient.state.currentUser;
      if (currentUser != null && currentUser.id == userId) {
        debugPrint('User $userId is already connected to StreamChat');
        return;
      }

      // Disconnect existing user if different user is connected
      if (currentUser != null && currentUser.id != userId) {
        debugPrint('Disconnecting existing user: ${currentUser.id}');
        await chatClient.disconnectUser();
      }

      // Only connect if not already connected or if different user
      if (chatClient.state.currentUser?.id != userId) {
        debugPrint('Connecting user to StreamChat: $userId');

        final streamUser = User(
          id: userId,
          name: userName ?? 'Guest User',
          image: 'https://i.imgur.com/fR9Jz14.png',
          extraData: {'email': userEmail ?? '', 'role': 'customer'},
        );

        final token = chatClient.devToken(userId);

        await chatClient
            .connectUser(streamUser, token.rawValue)
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw Exception('Chat connection timeout after 30 seconds');
              },
            );

        debugPrint('Successfully connected user $userId to StreamChat');
      }
    } catch (e) {
      debugPrint('Error connecting user to StreamChat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chat service temporarily unavailable: ${e.toString()}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxHeight < 650;

            return AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: size.width * 0.08,
                        vertical: isSmall ? 12 : 20,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight - (isSmall ? 40 : 60),
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const Spacer(),
                              _buildHeader(isSmall),
                              SizedBox(height: isSmall ? 24 : 40),
                              _buildLoginForm(),
                              SizedBox(height: isSmall ? 20 : 32),
                              _buildSignUpPrompt(),
                              const Spacer(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmall) {
    return Column(
      children: [
        Container(
          width: isSmall ? 110 : 130,
          height: isSmall ? 110 : 130,
          child: Image.asset(
            'assets/AutoMateLogoWithoutBackground.png',
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.directions_car_rounded,
                size: isSmall ? 36 : 40,
                color: primaryColor,
              );
            },
          ),
        ),
        SizedBox(height: isSmall ? 6 : 12),
        Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: isSmall ? 24 : 26,
            fontWeight: FontWeight.bold,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your trusted vehicle service companion',
          style: TextStyle(
            fontSize: isSmall ? 14 : 16,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildEmailField(),
            const SizedBox(height: 16),
            _buildPasswordField(),
            const SizedBox(height: 12),
            _buildRememberMeAndForgotPassword(),
            const SizedBox(height: 20),
            _buildLoginButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      validator: Validators.email,
      decoration: _inputDecoration(
        label: 'Email',
        hint: 'Enter your email',
        icon: Icons.email_outlined,
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      validator: Validators.password,
      onFieldSubmitted: (_) => _handleLogin(),
      decoration: _inputDecoration(
        label: 'Password',
        hint: 'Enter your password',
        icon: Icons.lock_outline,
        suffix: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.grey.shade600,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: primaryColor),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryColor, width: 1.8),
      ),
    );
  }

  Widget _buildRememberMeAndForgotPassword() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (v) => setState(() => _rememberMe = v ?? false),
                activeColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Text(
                'Remember me',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: _handleForgotPassword,
          child: const Text(
            'Forgot Password?',
            style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 3,
        ),
        child:
            _isLoading
                ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                : const Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: Colors.white,
                  ),
                ),
      ),
    );
  }

  Widget _buildSignUpPrompt() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account?",
          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
        ),
        TextButton(
          onPressed: () => Navigator.pushNamed(context, '/register/personal'),
          child: const Text(
            'Sign Up',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
