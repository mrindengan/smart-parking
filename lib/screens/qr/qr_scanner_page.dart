import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({Key? key}) : super(key: key);

  @override
  _QRScannerPageState createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool isProcessing = false;

  @override
  void dispose() {
    // Dispose MobileScanner or camera resources here
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

  Future<void> _processQRCode(String scannedSlot) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('User not authenticated.');
        return;
      }

      final userId = user.uid;
      print('Debug: Scanned Slot -> $scannedSlot');
      print('Debug: User ID -> $userId');

      final slotSnapshot = await FirebaseDatabase.instance
          .ref('parkingSlots/$scannedSlot')
          .get();

      if (!slotSnapshot.exists) {
        _showError('Invalid parking slot.');
        return;
      }

      final slotData = Map<String, dynamic>.from(slotSnapshot.value as Map);
      print('Debug: Slot Data -> $slotData');

      final reservedBy = slotData['reservedBy'] as String?;
      final isAvailable = slotData['isAvailable'] as bool? ?? false;

      // Retrieve user data to check for reservations
      final userSnapshot =
          await FirebaseDatabase.instance.ref('users/$userId').get();
      if (!userSnapshot.exists) {
        _showError('User data not found.');
        return;
      }

      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
      final String? reservedSlot = userData['reservedSlot'];

      // Check for upcoming reservations
      final upcomingSnapshot = await FirebaseDatabase.instance
          .ref('parkingSlots/$scannedSlot/upcomingReservations')
          .get();

      bool hasUpcomingReservation = false;
      if (upcomingSnapshot.exists) {
        final upcomingReservations =
            Map<String, dynamic>.from(upcomingSnapshot.value as Map);

        final now = DateTime.now();
        for (final reservation in upcomingReservations.values) {
          final checkIn = reservation['checkIn'] as String?;
          final date = reservation['date'] as String?;

          if (checkIn != null && date != null) {
            final checkInTime = _parseDateTime(checkIn, date);

            if (checkInTime != null &&
                now.isAfter(checkInTime.subtract(const Duration(hours: 2))) &&
                now.isBefore(checkInTime)) {
              hasUpcomingReservation = true;
              break;
            }
          } else {
            print(
                'Debug: Either checkIn or date is null. Skipping reservation.');
          }
        }
      }

      print('Debug: Reserved By -> $reservedBy');
      print('Debug: Is Available -> $isAvailable');
      print('Debug: Has Upcoming Reservation -> $hasUpcomingReservation');
      print('Debug: User Reserved Slot -> $reservedSlot');

      // Handle check-in logic for reserved users
      if (reservedSlot != null && reservedSlot == scannedSlot) {
        if (reservedBy == userId || reservedBy == null) {
          await _handleCheckIn(
            slotId: scannedSlot,
            userId: userId,
            isReservedUser: true,
          );
        } else {
          _showError('This slot is reserved by another user.');
        }
        return;
      }

      // Handle check-in logic for regular users
      if (reservedSlot == null && isAvailable && !hasUpcomingReservation) {
        await _handleCheckIn(
          slotId: scannedSlot,
          userId: userId,
          isReservedUser: false,
        );
        return;
      }

      // Handle invalid scenarios
      if (reservedSlot != null && reservedSlot != scannedSlot) {
        _showError(
            'Invalid slot. Please check in at your reserved slot: $reservedSlot.');
      } else if (hasUpcomingReservation) {
        _showError('This slot has an upcoming reservation.');
      } else {
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
  }) async {
    try {
      final userRef = FirebaseDatabase.instance.ref('users/$userId');
      final slotRef = FirebaseDatabase.instance.ref('parkingSlots/$slotId');
      final reservationRef =
          FirebaseDatabase.instance.ref('reservations/$userId');

      String? reservationId;

      // Handle upcoming reservations for reserved users
      if (isReservedUser) {
        final upcomingSnapshot =
            await slotRef.child('upcomingReservations').get();
        if (upcomingSnapshot.exists) {
          final upcomingReservations =
              Map<String, dynamic>.from(upcomingSnapshot.value as Map);

          // Identify the reservation for this user
          final entry = upcomingReservations.entries.firstWhere(
            (entry) => entry.value['userId'] == userId,
            orElse: () => MapEntry('', {}),
          );

          if (entry.key.isNotEmpty) {
            reservationId = entry.key;

            // Remove the reservation from upcomingReservations
            await slotRef.child('upcomingReservations/$reservationId').remove();
          }
        }
      }

      // Update user state
      await userRef.update({
        'isCheckedIn': true,
        'currentSlot': slotId,
      });

      // Update slot state
      await slotRef.update({
        'isAvailable': false,
        'reservedBy': isReservedUser ? null : userId,
      });

      // Update reservation status for reserved users
      if (isReservedUser && reservationId != null) {
        await reservationRef.child(reservationId).update({
          'status': 'CheckedIn',
          'checkIn': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${isReservedUser ? 'Reserved' : 'Regular'} Check-In successful!'),
          ),
        );
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } catch (e) {
      print('Error during check-in: $e');
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
                  onDetect: (capture) async {
                    final List<Barcode> barcodes = capture.barcodes;

                    if (isProcessing || barcodes.isEmpty) return;

                    setState(() => isProcessing = true);

                    final String? scannedSlot = barcodes.first.rawValue;
                    if (scannedSlot != null) {
                      await _processQRCode(scannedSlot);
                    } else {
                      _showError('Invalid QR Code');
                    }

                    setState(() => isProcessing = false);
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
