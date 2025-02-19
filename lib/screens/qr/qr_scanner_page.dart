import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({Key? key}) : super(key: key);

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool isProcessing = false;
  MobileScannerController scannerController = MobileScannerController();
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    startScanner(); // Start the scanner with a delay
  }

  @override
  void dispose() {
    try {
      scannerController.stop(); // Stop the scanner
    } catch (e) {
      print('Error stopping scanner: $e');
    }
    scannerController.dispose(); // Properly dispose of the scanner
    _subscription
        ?.cancel(); // Cancel any active listeners to avoid memory leaks
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } else {
      print('Error: Widget is unmounted. Cannot show error message: $message');
    }
  }

  Future<void> startScanner() async {
    await Future.delayed(Duration(seconds: 1)); // Small delay
    if (mounted) {
      try {
        scannerController.start();
      } catch (e) {
        print('Error starting scanner: $e');
      }
    }
  }

  Future<void> _processQRCode(String scannedSlot) async {
    try {
      if (!mounted) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('User not authenticated.');
        return;
      }

      final userId = user.uid;
      print('Debug: Scanned Slot -> $scannedSlot');
      print('Debug: User ID -> $userId');

      // 🔹 Fetch user's active reservation
      final reservationSnapshot =
          await FirebaseDatabase.instance.ref('reservations/$userId').get();

      String? reservedSlot;
      String? matchingReservationId;
      bool hasActiveReservation = false;
      final now = DateTime.now();

      if (reservationSnapshot.exists) {
        final reservations =
            Map<String, dynamic>.from(reservationSnapshot.value as Map);

        for (final entry in reservations.entries) {
          final reservation = Map<String, dynamic>.from(entry.value);
          final checkIn = reservation['checkIn'] as String?;
          final date = reservation['date'] as String?;
          final slotId = reservation['slot'];
          final status = reservation['status'];

          if (slotId == null || checkIn == null || date == null) continue;

          final checkInTime = _parseDateTime(checkIn, date);

          if (status == "Reserved" &&
              checkInTime != null &&
              now.isAfter(checkInTime)) {
            hasActiveReservation = true;
            reservedSlot = slotId;
            matchingReservationId = entry.key;
            break;
          }
        }
      }

      print('Debug: Reserved Slot -> $reservedSlot');
      print('Debug: Scanned Slot -> $scannedSlot');
      print('Debug: Matching Reservation ID -> $matchingReservationId');

      // ✅ Reserved users: Allow check-in to reserved slot
      if (reservedSlot != null &&
          reservedSlot == scannedSlot &&
          hasActiveReservation) {
        print('✅ User is checking into their reserved slot.');
        await _handleCheckIn(
          slotId: scannedSlot,
          userId: userId,
          isReservedUser: true,
          reservationId: matchingReservationId,
        );
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 🔹 Check slot availability for regular users
      final slotDataRef =
          FirebaseDatabase.instance.ref('parkingSlots/$scannedSlot');
      final slotSnapshot = await slotDataRef.get();

      if (!slotSnapshot.exists) {
        _showError('Invalid parking slot.');
        return;
      }

      final slotData = Map<String, dynamic>.from(slotSnapshot.value as Map);
      final isAvailable = slotData['isAvailable'] as bool? ?? false;
      final upcomingReservations =
          slotData['upcomingReservations'] as Map<dynamic, dynamic>?;

      print('Debug: Slot Data -> $slotData');
      print('Debug: Is Available -> $isAvailable');

      // 🔹 Check for upcoming reservations (Regular users only)
      if (reservedSlot == null && isAvailable && upcomingReservations != null) {
        for (final reservationEntry in upcomingReservations.entries) {
          final upcoming = Map<String, dynamic>.from(reservationEntry.value);
          final checkIn = upcoming['checkIn'] as String?;
          final date = upcoming['date'] as String?;

          if (checkIn == null || date == null) continue;

          final upcomingCheckInTime = _parseDateTime(checkIn, date);

          if (upcomingCheckInTime != null &&
              now.add(const Duration(hours: 2)).isAfter(upcomingCheckInTime)) {
            _showError('This slot has an upcoming reservation within 2 hours.');
            return;
          }
        }
      }

      // ✅ Proceed with regular user check-in
      if (reservedSlot == null && isAvailable) {
        await _handleCheckIn(
          slotId: scannedSlot,
          userId: userId,
          isReservedUser: false,
        );
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      // 🔹 Handle invalid scenarios
      if (reservedSlot != null && reservedSlot != scannedSlot) {
        _showError(
            'Invalid slot. Please check in at your reserved slot: $reservedSlot.');
      } else if (!isAvailable && !hasActiveReservation) {
        _showError('This slot is currently occupied.');
      }
    } catch (e, stackTrace) {
      print('Debug: Error -> $e');
      print('Debug: Stack Trace -> $stackTrace');
      _showError('Error processing QR Code: $e');
    }
  }

  Future<void> _handleCheckIn({
    required String slotId,
    required String userId,
    required bool isReservedUser,
    String? reservationId,
  }) async {
    try {
      final userRef = FirebaseDatabase.instance.ref('users/$userId');
      final reservationRef =
          FirebaseDatabase.instance.ref('reservations/$userId/$reservationId');

      print('DEBUG: Starting check-in process for slot $slotId');

      // 🔹 Fetch reservation slot (Reserved users only)
      String? reservationSlotId;
      if (isReservedUser && reservationId != null) {
        final reservationSnapshot = await reservationRef.get();
        if (reservationSnapshot.exists) {
          final reservationData =
              Map<String, dynamic>.from(reservationSnapshot.value as Map);
          reservationSlotId = reservationData['slot'];
        }
      }

      print('Debug: Reservation Slot ID -> $reservationSlotId');
      print('Debug: Scanned Slot ID -> $slotId');

      // ✅ Validate reserved user slot match
      if (isReservedUser && reservationSlotId != slotId) {
        _showError(
            'Invalid slot. Please check in at your reserved slot: $reservationSlotId.');
        return;
      }

      // 🔹 Fetch slot data (Reserved or regular users)
      Map<String, dynamic> slotData = {};
      if (isReservedUser) {
        final reservedSlotSnapshot = await reservationRef.get();
        if (!reservedSlotSnapshot.exists) {
          _showError('Slot data not found in reservations.');
          return;
        }
        slotData = Map<String, dynamic>.from(reservedSlotSnapshot.value as Map);
      } else {
        final slotRef = FirebaseDatabase.instance.ref('parkingSlots/$slotId');
        final slotSnapshot = await slotRef.get();
        if (!slotSnapshot.exists) {
          _showError('Slot data not found in parkingSlots.');
          return;
        }
        slotData = Map<String, dynamic>.from(slotSnapshot.value as Map);
      }

      final isAvailable = slotData['isAvailable'] as bool? ?? false;

      print('Debug: Slot Data -> $slotData');
      print('Debug: Is Available -> $isAvailable');

      // ✅ Validate slot availability (Regular users only)
      if (!isReservedUser && !isAvailable) {
        _showError('This slot is currently occupied.');
        return;
      }

      // ✅ Update User Check-In Status
      await userRef.update({
        'isCheckedIn': true,
        'currentSlot': slotId,
      });

      // ✅ Update Parking Slot with `databaseChangeTime`
      final slotRef = FirebaseDatabase.instance.ref('parkingSlots/$slotId');
      await slotRef.update({
        'isAvailable': false,
        if (!isReservedUser) 'reservedBy': userId,
        'databaseChangeTime': ServerValue.timestamp, // 🟡 Add server timestamp
      });

      // ✅ Update Reservation Status (For Reserved Users Only)
      if (isReservedUser && reservationId != null) {
        await reservationRef.update({
          'status': 'CheckedIn',
          'checkIn': DateTime.now().toIso8601String(),
        });
      }

      print('DEBUG: Check-in successful for slot $slotId with timestamp.');
    } catch (e, stackTrace) {
      print('Error during check-in: $e');
      print('Stack Trace: $stackTrace');
      _showError('Error during check-in: $e');
    }
  }

  DateTime? _parseDateTime(String? time, String? date) {
    if (time == null || date == null || time.isEmpty || date.isEmpty) {
      print('Debug: Time or Date is null or empty. Returning null.');
      return null; // Ensure null is returned for invalid input
    }

    try {
      final dateParts = date.split('-'); // Format: DD-MM-YYYY
      final timeParts = time.split(':'); // Format: HH:MM AM/PM

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1].split(' ')[0]);
      final isPM = time.contains('PM');
      final parsedHour = isPM ? (hour % 12) + 12 : hour;

      return DateTime(
        int.parse(dateParts[2]), // Year
        int.parse(dateParts[1]), // Month
        int.parse(dateParts[0]), // Day
        parsedHour,
        minute,
      );
    } catch (e) {
      print('Error parsing reservation time: $e');
      return null; // Return null if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        centerTitle: true,
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // QR Scanner Area
          Column(
            children: [
              Container(
                color: Colors.blue.withOpacity(0.1),
                height: 200,
                child: Center(
                  child: Text(
                    'Align the QR code within the frame to scan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: MobileScanner(
                  controller: scannerController,
                  onDetect: (capture) async {
                    final List<Barcode> barcodes = capture.barcodes;

                    if (isProcessing || barcodes.isEmpty) return;

                    setState(() => isProcessing = true);

                    final String? scannedSlot = barcodes.first.rawValue;
                    if (scannedSlot != null) {
                      try {
                        await _processQRCode(scannedSlot);
                      } catch (e) {
                        _showError('Error processing QR Code: $e');
                      }
                    } else {
                      _showError('Invalid QR Code');
                    }

                    await Future.delayed(Duration(
                        milliseconds: 500)); // Delay before allowing next scan

                    if (mounted) {
                      setState(() => isProcessing = false);
                    }
                  },
                ),
              ),
            ],
          ),

          // Loading Indicator
          if (isProcessing)
            Center(
              child: Container(
                color: Colors.black54,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Processing QR Code...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
