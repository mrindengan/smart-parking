import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class NavigationBar extends StatelessWidget {
  const NavigationBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  final int currentIndex;
  final Function(int) onTap;

  Widget _buildDynamicButton(bool isCheckedIn) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isCheckedIn ? Colors.red : Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isCheckedIn ? Icons.exit_to_app : Icons.qr_code_scanner,
        color: Colors.white,
        size: 30,
      ),
    );
  }

  void _showCheckOutConfirmation(BuildContext context, String userId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Check Out'),
          content: const Text('Are you sure you want to check out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _performCheckOut(context, userId);
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performCheckOut(BuildContext context, String userId) async {
    try {
      // Reference to the user node
      final userRef = FirebaseDatabase.instance.ref('users/$userId');
      final reservationsRef =
          FirebaseDatabase.instance.ref('reservations/$userId');
      final historyRef = FirebaseDatabase.instance.ref('history/$userId');
      final userSnapshot = await userRef.get();

      if (!userSnapshot.exists) {
        throw Exception('User data not found.');
      }

      // Extract user data
      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
      final String? currentSlot = userData['currentSlot'];
      final bool isCheckedIn = userData['isCheckedIn'] ?? false;

      // Validation: Ensure user is checked in and has a valid slot
      if (!isCheckedIn || currentSlot == null) {
        throw Exception('No active check-in or reservation found.');
      }

      // Reference to the parking slot node
      final slotRef =
          FirebaseDatabase.instance.ref('parkingSlots/$currentSlot');
      final slotSnapshot = await slotRef.get();

      if (!slotSnapshot.exists) {
        throw Exception('Parking slot not found.');
      }

      // Check for active reservations
      final reservationsSnapshot = await reservationsRef.get();
      bool isReservationHandled = false;

      if (reservationsSnapshot.exists) {
        final reservations =
            Map<String, dynamic>.from(reservationsSnapshot.value as Map);

        // Locate the active reservation associated with the current slot
        final activeReservationEntry = reservations.entries.firstWhere(
          (entry) => entry.value['slot'] == currentSlot,
          orElse: () => MapEntry('', {}),
        );

        if (activeReservationEntry.key.isNotEmpty) {
          final String reservationId = activeReservationEntry.key;
          final reservationData = activeReservationEntry.value;

          // Move reservation to history node
          await historyRef.child(reservationId).set({
            ...reservationData,
            'status': 'CheckedOut',
            'checkOut': DateTime.now().toIso8601String(),
          });

          // Remove reservation from reservations node
          await reservationsRef.child(reservationId).remove();

          // Remove reservation from upcomingReservations under the parking slot node
          await slotRef.child('upcomingReservations/$reservationId').remove();

          print(
              'DEBUG: Reservation $reservationId moved to history and removed from reservations and upcomingReservations.');
          isReservationHandled = true;
        }
      }

      if (!isReservationHandled) {
        print(
            'DEBUG: No active reservation found. Performing regular check-out.');
        await historyRef.push().set({
          'slot': currentSlot,
          'status': 'CheckedOut',
          'checkOut': DateTime.now().toIso8601String(),
          'userId': userId,
        });
      }

      // Update parking slot state
      await slotRef.update({
        'isAvailable': true,
        'reservedBy': null,
      });

      // Update user state
      await userRef.update({
        'isCheckedIn': false,
        'currentSlot': null,
      });

      print('DEBUG: Parking slot $currentSlot marked as available.');
      print('DEBUG: User $userId state updated.');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked out successfully!')),
      );
      Navigator.pushReplacementNamed(context, '/dashboard');
    } catch (e, stackTrace) {
      print('ERROR during check-out: $e');
      print('STACK TRACE: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during check-out: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final user = FirebaseAuth.instance.currentUser;

        if (user == null) {
          return const Center(
            child: Text('No user logged in.'),
          );
        }

        final userId = user.uid;

        // Listen to the isCheckedIn value in real-time
        return StreamBuilder(
          stream: FirebaseDatabase.instance
              .ref('users/$userId/isCheckedIn')
              .onValue,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            final isCheckedIn = snapshot.data!.snapshot.value
                as bool; // Get the isCheckedIn value

            return BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: (index) {
                if (index == 2) {
                  // Check-In/Check-Out button logic
                  if (isCheckedIn) {
                    _showCheckOutConfirmation(context, userId);
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/qrScanner', // Navigate to QR Scanner
                    );
                  }
                } else {
                  onTap(index); // Handle other navigation buttons
                }
              },
              backgroundColor: Colors.blue,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white70,
              type: BottomNavigationBarType.fixed,
              elevation: 8.0,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: 'Home',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.event_available),
                  label: 'Active',
                ),
                // Dynamic Check-In/Check-Out Button
                BottomNavigationBarItem(
                  icon: _buildDynamicButton(isCheckedIn),
                  label: isCheckedIn ? 'Check Out' : 'Check In',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            );
          },
        );
      },
    );
  }
}
