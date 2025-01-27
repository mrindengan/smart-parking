import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:io';

class AppState with ChangeNotifier {
  AppState() {
    print('AppState initialized.');
    _initializeAuthStateListener();
    _initializeParkingSlotListener();
    _initializeReservationListener();
    _initializeMessaging();
    _startPeriodicSlotUpdates();
    listenToCheckInStatus();
  }

  // User State
  User? currentUser;

  bool isCheckIn = false; // Track Check-In status
  bool isLoggedIn = false;
  int? lastUpdated; // Store the most recent update timestamp
  // Parking Slots (Real-Time Data)
  Map<String, Map<String, dynamic>> parkingSlots = {}; // Parking Slots Data

  Timer? periodicTimer; // Timer for periodic slot updates

  // Firebase References
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  File? _profileImage;
  final _profileImageController = StreamController<File?>.broadcast();

  @override
  void dispose() {
    periodicTimer?.cancel(); // Cancel timer to avoid memory leaks
    _profileImageController.close();
    super.dispose();
  }

  Stream<File?> get profileImageStream => _profileImageController.stream;

  File? get profileImage => _profileImage;

  // Listen to Check-In Status from Firebase
  void listenToCheckInStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    _dbRef.child('users/$userId/isCheckedIn').onValue.listen((event) {
      if (event.snapshot.exists) {
        final updatedStatus = event.snapshot.value as bool;
        if (isCheckIn != updatedStatus) {
          isCheckIn = updatedStatus; // Update local state
          notifyListeners(); // Notify UI
          print('isCheckIn updated to: $isCheckIn from database');
        }
      }
    });
  }

  // Update Check-In Status in Firebase
  Future<void> updateCheckInStatus(bool status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    await _dbRef.child('users/$userId').update({'isCheckedIn': status});
    print('Database isCheckedIn updated to: $status');
  }

  /// Handles the check-out logic for a user
  Future<void> checkOut(String reservationId, String slotId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated.');
      }

      final String userId = user.uid;

      // Fetch the reservation data
      final reservationSnapshot =
          await _dbRef.child('reservations/$userId/$reservationId').get();

      if (!reservationSnapshot.exists) {
        throw Exception('Reservation not found.');
      }

      final reservationData =
          Map<String, dynamic>.from(reservationSnapshot.value as Map);

      // Parse reservation times for validation
      final String? checkInTime = reservationData['checkIn'] as String?;
      final String? reservationDate = reservationData['date'] as String?;
      final DateTime? parsedCheckIn =
          _parseDateTime(checkInTime, reservationDate);

      if (parsedCheckIn == null || DateTime.now().isBefore(parsedCheckIn)) {
        throw Exception(
            'Invalid check-in time or reservation is not yet active.');
      }

      // Move reservation to history
      await _dbRef.child('history/$userId/$reservationId').set({
        ...reservationData,
        'status': 'Checked Out',
        'checkOut': DateTime.now().toIso8601String(),
      });

      // Remove reservation from active reservations
      await _dbRef.child('reservations/$userId/$reservationId').remove();

      // Update the parking slot to be available
      await _dbRef.child('parkingSlots/$slotId').update({
        'isAvailable': true,
        'reservedBy': null,
      });

      // Update user's check-in status
      await _dbRef.child('users/$userId').update({
        'isCheckedIn': false,
        'currentSlot': null,
      });

      print('Check-Out successful for reservation: $reservationId');
      try {
        notifyListeners();
      } catch (notifyError) {
        print('Error notifying listeners: $notifyError');
      }
    } catch (e) {
      print('Error during check-out: $e');
      throw Exception('Failed to complete check-out: $e');
    }
  }

  // Register Method
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      print('User created in Firebase Authentication with UID: $uid');

      await _dbRef.child('users/$uid').set({
        'name': name,
        'email': email,
        'studentId': null,
        'profilePicture': null,
        'isCheckedIn': false,
        'currentSlot': null,
      });

      print('User details successfully saved to Realtime Database!');
    } catch (e) {
      print('Error during registration: ${e.toString()}');
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  // Log-In Method
  Future<void> login(String email, String password) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password);

      final String uid = userCredential.user!.uid;

      print('User signed in successfully with UID: $uid');

      final snapshot = await _dbRef.child('users/$uid').get();
      if (snapshot.exists) {
        print('User data fetched: ${snapshot.value}');
      } else {
        print('No user data found for UID: $uid');
        throw Exception('No user data found in database');
      }
    } catch (e) {
      print('Error during login: ${e.toString()}');
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  // Logout Method
  Future<void> logout() async {
    await _auth.signOut();
  }

  // Initialize Firebase Messaging
  void _initializeMessaging() async {
    print('Initializing Firebase Messaging...');

    // Request notification permissions
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('Notification permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      try {
        // Retrieve the FCM token
        String? token = await _messaging.getToken();
        if (token != null) {
          print('FCM Token: $token');
          _saveTokenToDatabase(token); // Save token to Firebase
        } else {
          print('Failed to retrieve FCM token.');
        }
      } catch (e) {
        print('Error retrieving FCM token: $e');
      }
    } else {
      print('Notification permissions denied.');
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      print('FCM Token refreshed: $newToken');
      _saveTokenToDatabase(newToken); // Update token in Firebase
    });

    // Handle foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground notification received: ${message.notification?.body}');
    });

    // Handle notification clicks
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification clicked: ${message.data}');
    });

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Save FCM token to Firebase Realtime Database
  Future<void> _saveTokenToDatabase(String token) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('No authenticated user found to associate token.');
        return;
      }

      final userId = user.uid;
      await _dbRef.child('users/$userId').update({'fcmToken': token});
      print('FCM token saved to Firebase for user: $userId');
    } catch (e) {
      print('Error saving FCM token to Firebase: $e');
    }
  }

  // Background message handler
  @pragma('vm:entry-point')
  static Future<void> _firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    print('Handling background message: ${message.messageId}');
  }

  // Listen to Firebase Authentication State
  void _initializeAuthStateListener() {
    _auth.authStateChanges().listen((user) {
      currentUser = user;
      if (user != null) {
        print('User signed in: ${user.uid}');
      } else {
        print('User signed out.');
      }
      notifyListeners(); // Notify listeners of authentication state changes
    });
  }

  // Listen to Real-Time Parking Slot Data
  void _initializeParkingSlotListener() {
    print('Initializing Parking Slot Listener...');
    _dbRef.child('parkingSlots').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>? ?? {};
      parkingSlots = data.map((key, value) =>
          MapEntry(key.toString(), Map<String, dynamic>.from(value)));
      print('Parking slots updated: $parkingSlots');
      notifyListeners(); // Notify UI of slot updates
    }, onError: (error) {
      print('Error listening to parking slot data: $error');
    });
  }

  // Listen to Reservation Data for Slot Updates
  void _initializeReservationListener() {
    print('Initializing Reservation Listener...');
    _dbRef.child('reservations').onValue.listen((event) {
      if (!event.snapshot.exists) {
        print('No reservations found in the database.');
        return;
      }

      final reservations =
          Map<String, dynamic>.from(event.snapshot.value as Map);
      print('Reservations fetched: $reservations');
      _updateSlotsBasedOnReservations(reservations);
    }, onError: (error) {
      print('Error listening to reservation data: $error');
    });
  }

  // Periodic Updates for Slots
  void _startPeriodicSlotUpdates() {
    print('Starting periodic slot updates...');
    periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      print('Running periodic slot update...');
      final snapshot = await _dbRef.child('reservations').get();
      if (snapshot.exists) {
        final reservations = Map<String, dynamic>.from(snapshot.value as Map);
        print('Periodic reservations fetched: $reservations');
        _updateSlotsBasedOnReservations(reservations);
      } else {
        print('No reservations found during periodic update.');
      }
    });
  }

  // Update Slots Based on Reservations
  void _updateSlotsBasedOnReservations(Map<String, dynamic> reservations) {
    final now = DateTime.now();
    final Map<String, bool> slotStatus =
        {}; // Tracks the current status for each slot

    for (final userEntry in reservations.entries) {
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final entry in userReservations.entries) {
        final reservation = Map<String, dynamic>.from(entry.value);
        final slotId = reservation['slot'];

        if (slotId == null || slotId.runtimeType != String) {
          print('Invalid slotId for reservation: $reservation');
          continue; // Skip processing if slotId is invalid
        }

        try {
          // Parse reservation times
          final checkInTime =
              _parseTime(reservation['checkIn'], reservation['date']);
          final checkOutTime =
              _parseTime(reservation['checkOut'], reservation['date']);

          print('-----------------------');
          print('Processing reservation: ${entry.key}');
          print('Slot: $slotId');
          print('Check-In: $checkInTime, Check-Out: $checkOutTime');
          print('Current Time: $now');
          print('-----------------------');

          // Active Reservation Logic
          if (now.isAfter(checkInTime) && now.isBefore(checkOutTime)) {
            slotStatus[slotId] = true; // Mark slot as occupied
            print('Slot $slotId is marked as occupied (Active Reservation).');
          } else if (now.isAfter(checkOutTime)) {
            // Past Reservation Logic
            slotStatus[slotId] = false; // Mark slot as available
            print('Slot $slotId is marked as available (Past Reservation).');
          } else {
            // Future Reservation Logic
            print('Slot $slotId is reserved for the future. Ignored.');
          }
        } catch (e) {
          print('Error processing reservation for slot $slotId: $e');
        }
      }
    }

    // Update Slot Availability in Database
    for (final slotEntry in slotStatus.entries) {
      final slotId = slotEntry.key;
      final isOccupied = slotEntry.value;

      print('Updating slot $slotId in the database...');
      _updateSlotAvailability(slotId, isOccupied).then((_) {
        print('Slot $slotId updated: isAvailable=${!isOccupied}');
      }).catchError((e) {
        print('Error updating slot $slotId: $e');
      });
    }
  }

  // Parse Time from Reservation Data
  DateTime _parseTime(String time, String date) {
    final dateParts = date.split('-');
    final timeParts = time.split(':');

    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1].split(' ')[0]);
    final isPM = time.contains('PM');
    final parsedHour = isPM ? (hour % 12) + 12 : hour;

    return DateTime(
      int.parse(dateParts[2]),
      int.parse(dateParts[1]),
      int.parse(dateParts[0]),
      parsedHour,
      minute,
    );
  }

  // Update Slot Availability in Firebase
  Future<void> _updateSlotAvailability(String slotId, bool isOccupied) async {
    try {
      await _dbRef.child('parkingSlots/$slotId').update({
        'isAvailable': !isOccupied,
        'reservedBy': isOccupied ? currentUser?.uid : null,
      });
      print(
          'Slot $slotId updated: isAvailable=${!isOccupied}, reservedBy=${isOccupied ? currentUser?.uid : null}');
    } catch (e) {
      print('Error updating slot availability for Slot $slotId: $e');
    }
  }
}

DateTime? _parseDateTime(String? time, String? date) {
  if (time == null || date == null) {
    print('DEBUG: Invalid time or date. Returning null.');
    return null;
  }

  try {
    final dateParts = date.split('-'); // Format: DD-MM-YYYY
    final timeParts = time.split(':'); // Format: HH:MM AM/PM
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1].split(' ')[0]);
    final isPM = time.toUpperCase().contains('PM');

    return DateTime(
      int.parse(dateParts[2]), // Year
      int.parse(dateParts[1]), // Month
      int.parse(dateParts[0]), // Day
      isPM ? (hour % 12) + 12 : hour,
      minute,
    );
  } catch (e) {
    print('Error parsing date/time: $e');
    return null;
  }
}
