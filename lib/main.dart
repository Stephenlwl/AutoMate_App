import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/register/personal_details_page.dart';
import 'pages/auth/register/registration_pending_page.dart';
import 'pages/auth/forgot_password_page.dart';
import 'pages/homepage/homepage.dart';
import 'pages/services/search_services_page.dart';
import 'pages/services/book_services_page.dart';
import 'pages/services/search_service_center_page.dart';
import 'pages/chat/customer_support_chat_page.dart';
import 'services/notification_service.dart';
import 'blocs/notification_bloc.dart';
import 'firebase_options.dart';
import 'package:stream_chat_flutter/stream_chat_flutter.dart';
import 'package:automate_application/pages/notification/notification.dart';
import 'package:automate_application/globals/navigation_service.dart';
import 'pages/towing_driver/driver_homepage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Create chat client once
  final chatClient = StreamChatClient(
    '3mj9hufw92nk',
    logLevel: Level.INFO,
  );

  runApp(MyApp(chatClient: chatClient));
}

class MyApp extends StatefulWidget {
  final StreamChatClient chatClient;
  const MyApp({super.key, required this.chatClient});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late NotificationBloc _notificationBloc;

  @override
  void initState() {
    super.initState();
    _notificationBloc = NotificationBloc(currentUserId: '');
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<NotificationBloc>.value(
          value: _notificationBloc,
        ),
      ],
      child: StreamChatTheme(
        data: StreamChatThemeData(
          colorTheme: StreamColorTheme.dark(
            accentPrimary: const Color(0xFF1F2A44),
          ),
        ),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          title: 'AutoMate - Car Repair Service',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B00)),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            useMaterial3: true,
          ),
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return StreamChat(
              client: widget.chatClient,
              child: child!,
            );
          },
          home: LoginPage(
            onLoginSuccess: (userId, userName, userEmail) {
              _notificationBloc.updateUserId(userId);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                NotificationService().initialize(
                  _notificationBloc,
                  userId: userId,
                  userName: userName,
                  userEmail: userEmail,
                );
              });
            },
          ),
          routes: {
            '/driver/home': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              final userName = args?['userName'] as String?;
              final userEmail = args?['userEmail'] as String?;
              final userData = args?['userData'] as Map<String, dynamic>?;

              if (userId == null) {
                return const Scaffold(
                  body: Center(child: Text('Driver ID is missing. Please restart the app.')),
                );
              }

              return DriverHomePage(
                userData: userData,
                userId: userId,
              );
            },
            '/home': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              final userName = args?['userName'] as String?;
              final userEmail = args?['userEmail'] as String?;

              if (userId == null || userName == null || userEmail == null) {
                return const Scaffold(
                  body: Center(child: Text('User ID, Name and Email are missing. Please restart the app.')),
                );
              }
              final notificationBloc = context.read<NotificationBloc>();
              notificationBloc.updateUserId(userId);

              return Homepage(
                userId: userId,
                chatClient: widget.chatClient,
                userName: userName,
                userEmail: userEmail,
                notificationBloc: notificationBloc,
              );
            },
            '/support-chat': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              if (args != null && args['userId'] != null && args['channel'] != null) {
                final userId = args['userId'] as String;
                final channel = args['channel'] as Channel;
                final notificationBloc = context.read<NotificationBloc>();
                notificationBloc.updateUserId(userId);

                return CustomerSupportChatPage(channel: channel);
              }
              return const Scaffold(
                body: Center(child: Text('Channel information missing')),
              );
            },
            'search-service-center': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              final userName = args?['userName'] as String?;
              final userEmail = args?['userEmail'] as String?;
              if (userId == null || userName == null || userEmail == null) {
                return const Scaffold(
                  body: Center(child: Text('User ID, Name and Email are missing. Please restart the app.')),
                );
              }
              final notificationBloc = context.read<NotificationBloc>();
              notificationBloc.updateUserId(userId);

              return SearchServiceCenterPage(
                userId: userId,
                userName: userName,
                userEmail: userEmail,
              );
            },
            'book-services': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              final serviceCenter = args?['serviceCenter'];
              if (userId == null) {
                return const Scaffold(
                  body: Center(child: Text('User ID missing')),
                );
              }
              final notificationBloc = context.read<NotificationBloc>();
              notificationBloc.updateUserId(userId);

              return BookServicePage(userId: userId, serviceCenter: serviceCenter);
            },
            'search-services': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              if (userId == null) {
                return const Scaffold(
                  body: Center(child: Text('User ID missing')),
                );
              }
              final notificationBloc = context.read<NotificationBloc>();
              notificationBloc.updateUserId(userId);

              return SearchServicesPage(userId: userId);
            },
            '/register/personal': (context) => const PersonalDetailsPage(),
            '/register/pending': (context) => const RegistrationPendingPage(),
            '/forgot-password': (context) => const ForgotPasswordPage(),
            '/login': (context) => const LoginPage(),
            '/notifications': (context) {
              final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
              final userId = args?['userId'] as String?;
              if (userId == null) {
                return const Scaffold(
                  body: Center(child: Text('User ID missing')),
                );
              }
              final notificationBloc = context.read<NotificationBloc>();
              notificationBloc.updateUserId(userId);
              return NotificationsPage(userId: userId);
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationBloc.close();
    super.dispose();
  }
}