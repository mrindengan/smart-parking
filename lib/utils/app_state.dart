import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:io';
import 'package:smartparking/utils/notifications_manager.dart';

class AppState with ChangeNotifier {
  AppState() {
    print('AppState initialized.');
    _initializeAuthStateListener();
    _initializeParkingSlotListener();
    _initializeReservationListener();
    _startPeriodicSlotUpdates();
    listenToCheckInStatus();
  }

  // User State
  User? currentUser;
  bool isAdmin = false; // New property for admin flag //
  bool isCheckIn = false; // Track Check-In status
  bool isLoggedIn = false;
  int? lastUpdated; // Store the most recent update timestamp
  // Parking Slots (Real-Time Data)
  Map<String, Map<String, dynamic>> parkingSlots = {}; // Parking Slots Data

  Timer? periodicTimer; // Timer for periodic slot updates

  // Firebase References
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
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

      // Fetch user data from Realtime Database
      final snapshot = await _dbRef.child('users/$uid').get();
      if (snapshot.exists) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        print('User data fetched: $userData');
        // Check if the user has an "isAdmin" flag set to true
        isAdmin = userData['isAdmin'] == true;
      } else {
        print('No user data found for UID: $uid');
        throw Exception('No user data found in database');
      }
      // Notify listeners if needed
      notifyListeners();
    } catch (e) {
      print('Error during login: ${e.toString()}');
      throw Exception('Login failed: ${e.toString()}');
    }
  }

  // Logout Method
  Future<void> logout() async {
    await _auth.signOut();
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
      _processReservationsAndUpdateSlots(reservations);
    }, onError: (error) {
      print('Error listening to reservation data: $error');
    });
  }

  void _startPeriodicSlotUpdates() {
    print('Starting periodic slot updates...');
    periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      print('Running periodic slot update...');

      // Fetch reservations from the database
      final snapshot = await _dbRef.child('reservations').get();
      if (snapshot.exists) {
        final reservations = Map<String, dynamic>.from(snapshot.value as Map);
        print('Periodic reservations fetched: $reservations');
        // Call the notification scenarios
        NotificationManager.handleCheckInReminders(reservations);
        NotificationManager.handleCheckOutReminders(reservations);
        await NotificationManager.handleMissedCheckIns(
          reservations,
          _archiveReservationAndUpdateSlot, // AppState method for database updates
        );
        await NotificationManager.handleOverdueCheckOuts(
          reservations,
          _archiveReservationAndUpdateSlot, // AppState method for database updates
        );
        _processReservationsAndUpdateSlots(reservations);
      } else {
        print('No reservations found during periodic update.');
      }
    });
  }

  Future<void> _processReservationsAndUpdateSlots(
      Map<String, dynamic> reservations) async {
    final now = DateTime.now();
    final Map<String, bool> slotStatus = {}; // Track slot availability
    final Map<String, String?> checkedInUsers =
        {}; // Track users who checked in

    for (final userEntry in reservations.entries) {
      final userId = userEntry.key; // Extract userId
      final userReservations = Map<String, dynamic>.from(userEntry.value);

      for (final entry in userReservations.entries) {
        final reservation = Map<String, dynamic>.from(entry.value);
        final slotId = reservation['slot'];

        if (slotId == null || slotId.runtimeType != String) {
          print('Invalid slotId for reservation: $reservation');
          continue;
        }

        try {
          final DateTime? checkInTime =
              _parseDateTime(reservation['checkIn'], reservation['date']);
          final DateTime? checkOutTime =
              _parseDateTime(reservation['checkOut'], reservation['date']);

          if (checkInTime == null || checkOutTime == null) {
            print(
                'Skipping reservation with invalid check-in or check-out time.');
            continue;
          }

          print('Processing reservation: ${entry.key}');
          print('Slot: $slotId');
          print('Check-In: $checkInTime, Check-Out: $checkOutTime');
          print('Current Time: $now');

          // ✅ Check if user is already checked in
          final userSnapshot = await FirebaseDatabase.instance
              .ref('users/$userId/isCheckedIn')
              .get();
          final bool isUserCheckedIn =
              userSnapshot.exists && userSnapshot.value == true;

          if (isUserCheckedIn) {
            checkedInUsers[slotId] = userId;
            print('Slot $slotId is occupied by checked-in user: $userId');
            continue; // Skip further processing for this slot
          }

          // ✅ Determine slot availability
          if (now.isAtSameMomentAs(checkInTime) ||
              (now.isAfter(checkInTime) && now.isBefore(checkOutTime))) {
            slotStatus[slotId] = true; // Mark slot as occupied
            print('Slot $slotId is marked as occupied.');
          } else if (now.isAfter(checkOutTime)) {
            slotStatus[slotId] = false; // Mark slot as available
            print('Slot $slotId is marked as available.');
          } else {
            print('Slot $slotId is reserved for the future.');
          }
        } catch (e) {
          print('Error processing reservation for slot $slotId: $e');
        }
      }
    }

    // ✅ Update slot availability with server timestamp
    for (final slotEntry in slotStatus.entries) {
      final slotId = slotEntry.key;
      final isOccupied = slotEntry.value;

      try {
        await _dbRef.child('parkingSlots/$slotId').update({
          'isAvailable': !isOccupied,
          'reservedBy': checkedInUsers.containsKey(slotId)
              ? checkedInUsers[slotId]
              : null,
          'databaseChangeTime':
              ServerValue.timestamp, // 🟡 Add server timestamp
        });
        print(
            'Slot $slotId updated: isAvailable=${!isOccupied}, timestamp recorded.');
      } catch (e) {
        print('Error updating slot availability for Slot $slotId: $e');
      }
    }
  }

  Future<void> _archiveReservationAndUpdateSlot(
    String userId,
    String reservationId,
    String slotId,
    String status,
  ) async {
    try {
      // ✅ Archive Reservation to History
      final reservationSnapshot =
          await _dbRef.child('reservations/$userId/$reservationId').get();

      if (reservationSnapshot.exists) {
        final reservationData =
            Map<String, dynamic>.from(reservationSnapshot.value as Map);

        await _dbRef.child('history/$userId/$reservationId').set({
          ...reservationData,
          'status': status,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // ✅ Remove from active reservations
        await _dbRef.child('reservations/$userId/$reservationId').remove();

        print(
            'Reservation $reservationId archived for user $userId with status: $status.');
      } else {
        print('No reservation found for ID: $reservationId and user: $userId.');
      }

      // ✅ Update Parking Slot with Server Timestamp
      await _dbRef.child('parkingSlots/$slotId').update({
        'isAvailable': true,
        'reservedBy': null,
        'databaseChangeTime': ServerValue.timestamp, // 🟡 Add server timestamp
      });

      print(
          'Slot $slotId marked as available with server timestamp and cleared of reservations.');
    } catch (e) {
      print('Error archiving reservation and updating slot: $e');
    }
  }

  DateTime? _parseDateTime(String? time, String? date) {
    if (time == null || date == null) {
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
}
