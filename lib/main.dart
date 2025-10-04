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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Then initialize notifications (requires Firebase to be initialized)
  await NotificationService().initialize();

  // Create chat client once
  final chatClient = StreamChatClient(
    '3mj9hufw92nk',
    logLevel: Level.INFO,
  );

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<NotificationBloc>(
          create: (context) => NotificationBloc(),
        ),
      ],
      child: MyApp(chatClient: chatClient),
    ),
  );
}

class MyApp extends StatelessWidget {
  final StreamChatClient chatClient;
  const MyApp({super.key, required this.chatClient});

  @override
  Widget build(BuildContext context) {
    return StreamChatTheme(
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
            client: chatClient,
            child: child!,
          );
        },
        home: const LoginPage(),
        routes: {
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
            return Homepage(
              userId: userId,
              chatClient: chatClient,
              userName: userName,
              userEmail: userEmail,
            );
          },
          '/support-chat': (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
            if (args != null && args['userId'] != null && args['channel'] != null) {
              final userId = args['userId'] as String;
              final channel = args['channel'] as Channel;
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
            return SearchServiceCenterPage(userId: userId, userName: userName, userEmail: userEmail,);
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
            return SearchServicesPage(userId: userId);
          },
          '/register/personal': (context) => const PersonalDetailsPage(),
          '/register/pending': (context) => const RegistrationPendingPage(),
          '/forgot-password': (context) => const ForgotPasswordPage(),
          // Add notification page route
          '/notifications': (context) => const NotificationsPage(),
        },
      ),
    );
  }
}