import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:smartparking/screens/dashboard_page.dart';
import 'package:smartparking/screens/history_page.dart';
import 'package:smartparking/screens/map_page.dart';
import 'package:smartparking/screens/profile_page.dart';
import 'package:smartparking/screens/qr/qr_scanner_page.dart';
import 'package:smartparking/utils/app_state.dart';
import 'package:smartparking/screens/login_page.dart';
import 'package:smartparking/utils/themes.dart';
import 'package:smartparking/screens/reservation_page.dart';
import 'package:smartparking/screens/active_reservations_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    print('Firebase initialized.');

    // Initialize Firebase Messaging
    await _initializeFirebaseMessaging();
  } catch (e) {
    print('Error during initialization: $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: const SmartParkingApp(),
    ),
  );
}

class SmartParkingApp extends StatelessWidget {
  const SmartParkingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Parking App',
      theme: AppThemes.lightTheme, // Default Light Theme
      darkTheme: AppThemes.darkTheme, // Optional Dark Theme
      themeMode: ThemeMode
          .light, // Change this to ThemeMode.system for system-wide theme
      home: StreamBuilder<User?>(
        stream:
            FirebaseAuth.instance.authStateChanges(), // Listen to auth state
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            print('Auth Stream Error: ${snapshot.error}');
            return const Center(child: Text('Something went wrong.'));
          }
          if (snapshot.hasData) {
            return const DashboardPage(); // Authenticated user
          }
          return const LoginPage(); // Unauthenticated user
        },
      ),
      routes: {
        '/login': (context) => LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/map': (context) => const MapPage(),
        '/reservation': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as String;
          return ReservationPage(
              selectedSlot: args); // Pass the required parameter
        },
        '/activeReservations': (context) => const ActiveReservationsPage(),
        '/history': (context) => const HistoryPage(),
        '/profile': (context) => const ProfilePage(),
        '/qrScanner': (context) => const QRScannerPage(),
      },
    );
  }
}

// Initialize Firebase Messaging
Future<void> _initializeFirebaseMessaging() async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request notification permissions
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  print('Notification permission status: ${settings.authorizationStatus}');

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    try {
      // Retrieve FCM Token
      String? token = await messaging.getToken();
      if (token != null) {
        print('FCM Token: $token');
        // Save token to Firebase (optional)
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final DatabaseReference dbRef = FirebaseDatabase.instance.ref();
          await dbRef.child('users/${user.uid}').update({'fcmToken': token});
          print('FCM Token saved to database.');
        }
      } else {
        print('Failed to retrieve FCM token.');
      }
    } catch (e) {
      print('Error retrieving FCM token: $e');
    }
  } else {
    print('User denied notification permissions.');
  }

  // Handle foreground notifications
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Foreground notification received: ${message.notification?.body}');
  });

  // Handle background notifications
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle notification clicks
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('Notification clicked: ${message.data}');
  });
}

// Background notification handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
}
