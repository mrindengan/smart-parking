import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:smartparking/screens/admin_dashboard_%5Bage.dart';
import 'package:smartparking/screens/admin_parking_slots_page.dart';
import 'package:smartparking/screens/admin_reservations_page.dart';
import 'package:smartparking/screens/dashboard_page.dart';
import 'package:smartparking/screens/history_page.dart';
import 'package:smartparking/screens/map_page.dart';
import 'package:smartparking/screens/profile_page.dart';
import 'package:smartparking/screens/qr/qr_scanner_page.dart';
import 'package:smartparking/utils/app_state.dart';
import 'package:smartparking/screens/login_page.dart';
import 'package:smartparking/utils/notifications_manager.dart';
import 'package:smartparking/utils/themes.dart';
import 'package:smartparking/screens/reservation_page.dart';
import 'package:smartparking/screens/active_reservations_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Initializing Notification Manager...');
  NotificationManager.initialize();
  try {
    // Initialize Firebase
    await Firebase.initializeApp();
    print('Firebase initialized.');
  } catch (e) {
    print('Error during Firebase initialization: $e');
  }

  print('Starting SmartParkingApp...');
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
    // Access AppState to ensure initialization
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Smart Parking App',
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: ThemeMode.light,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                print('Auth Stream Error: ${snapshot.error}');
                return const Center(child: Text('Something went wrong.'));
              }
              if (snapshot.hasData) {
                return appState.isAdmin
                    ? const AdminDashboardPage() // Admin user
                    : const DashboardPage(); // Authenticated user
              }
              return const LoginPage(); // Unauthenticated user
            },
          ),
          routes: {
            '/login': (context) => LoginPage(),
            '/dashboard': (context) => const DashboardPage(),
            '/admin-dashboard': (context) => const AdminDashboardPage(),
            '/adminReservations': (context) => const AdminReservationsPage(),
            '/adminParkingSlots': (context) => const AdminParkingSlotsPage(),
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
      },
    );
  }
}
