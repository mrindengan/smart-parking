import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../widgets/navigation_bar.dart' as custom;

class ActiveReservationsPage extends StatefulWidget {
  const ActiveReservationsPage({Key? key}) : super(key: key);

  @override
  _ActiveReservationsPageState createState() => _ActiveReservationsPageState();
}

class _ActiveReservationsPageState extends State<ActiveReservationsPage> {
  bool isLoading = true;
  Map<String, dynamic>? regularCheckIn; // Track regular check-ins
  List<Map<String, dynamic>> reservations = [];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _listenToReservations();
    _listenToRegularCheckIn();
  }

  void _listenToReservations() {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    _dbRef.child('reservations/$userId').onValue.listen((event) {
      if (!event.snapshot.exists) {
        setState(() {
          reservations = [];
          isLoading = false;
        });
        return;
      }

      final now = DateTime.now();
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final filteredReservations = data.entries
          .map((entry) {
            final reservation = Map<String, dynamic>.from(entry.value);
            final checkOutTime =
                _parseDateTime(reservation['checkOut'], reservation['date']);

            // Check for null before using isAfter
            if (checkOutTime != null && checkOutTime.isAfter(now)) {
              reservation['id'] = entry.key; // Add ID for Firebase reference
              return reservation;
            }
            return null;
          })
          .where((reservation) => reservation != null)
          .cast<Map<String, dynamic>>()
          .toList();

      // Dynamically reflect reservation changes
      setState(() {
        reservations = filteredReservations;
        isLoading = false;
      });
    });

    // Listen for real-time updates to user info
    _dbRef.child('users/$userId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final userData = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (userData['isCheckedIn'] == true) {
          setState(() {
            regularCheckIn = {
              'slot': userData['currentSlot'],
              'status': 'CheckedIn',
              'checkIn': userData['checkIn'],
              'checkOut': userData['checkOut'],
            };
          });
        } else {
          setState(() {
            regularCheckIn = null;
          });
        }
      }
    });
  }

  Future<void> _showExtendDialog(BuildContext context, String reservationId,
      Map<String, dynamic> reservation) async {
    TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (selectedTime != null) {
      DateTime? reservationDate =
          _parseDateTime('12:00 AM', reservation['date']);
      DateTime? currentCheckOut =
          _parseDateTime(reservation['checkOut'], reservation['date']);

      if (reservationDate == null || currentCheckOut == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error parsing reservation details.')),
        );
        return;
      }

      DateTime newCheckOut = DateTime(
        reservationDate.year,
        reservationDate.month,
        reservationDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );

      if (!newCheckOut.isAfter(currentCheckOut)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'New check-out time must be later than the current check-out time.'),
          ),
        );
        return;
      }

      if (selectedTime.hour < 5 || selectedTime.hour >= 21) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'New check-out time must be within working hours (5:00 AM to 9:00 PM).'),
          ),
        );
        return;
      }

      // Validate slot availability and conflicts
      bool slotAvailable = await _isSlotAvailable(reservation['slot']);
      if (!slotAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The slot is not available for extension.'),
          ),
        );
        return;
      }

      bool hasConflict = await _checkReservationConflict(
        reservation['slot'],
        newCheckOut,
        reservationId,
      );

      if (hasConflict) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'The new check-out time conflicts with another reservation.'),
          ),
        );
      } else {
        await _extendReservation(reservationId, newCheckOut);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reservation successfully extended.')),
        );
      }
    }
  }

  Future<bool> _isSlotAvailable(String slotId) async {
    try {
      final slotSnapshot = await _dbRef.child('parkingSlots/$slotId').get();
      if (!slotSnapshot.exists) {
        return false;
      }

      final slotData = Map<String, dynamic>.from(slotSnapshot.value as Map);

      // Slot must be available for extension
      return slotData['isAvailable'] ?? false;
    } catch (e) {
      print('Error checking slot availability: $e');
      return false;
    }
  }

  void _listenToRegularCheckIn() {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    _dbRef.child('users/$userId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final userData = Map<String, dynamic>.from(event.snapshot.value as Map);
        if (userData['isCheckedIn'] == true) {
          setState(() {
            regularCheckIn = {
              'slot': userData['currentSlot'],
              'status': 'CheckedIn',
            };
          });
        } else {
          setState(() {
            regularCheckIn = null;
          });
        }
      }
    });
  }

  Future<void> _extendReservation(
      String reservationId, DateTime newCheckOut) async {
    try {
      final reservationRef = FirebaseDatabase.instance.ref(
          'reservations/${FirebaseAuth.instance.currentUser!.uid}/$reservationId');

      await reservationRef.update({
        'checkOut': DateFormat('hh:mm a').format(newCheckOut), // Fixed usage
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation extended successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error extending reservation: $e')),
      );
    }
  }

  Future<bool> _checkReservationConflict(
      String slotId, DateTime newCheckOut, String currentReservationId) async {
    try {
      final reservationsSnapshot = await _dbRef.child('reservations').get();
      if (!reservationsSnapshot.exists) {
        return false; // No conflict if no reservations exist
      }

      final allReservations =
          Map<String, dynamic>.from(reservationsSnapshot.value as Map);

      for (final userReservations in allReservations.values) {
        final userResMap = Map<String, dynamic>.from(userReservations);

        for (final entry in userResMap.entries) {
          final res = Map<String, dynamic>.from(entry.value);

          // Skip the current reservation being extended
          if (entry.key == currentReservationId) {
            continue;
          }

          // Parse dates and check for conflicts
          final existingCheckIn = _parseDateTime(res['checkIn'], res['date']);
          final existingCheckOut = _parseDateTime(res['checkOut'], res['date']);

          if (res['slot'] == slotId &&
              existingCheckIn != null &&
              existingCheckOut != null) {
            // Conflict conditions:
            // 1. New checkout is after an existing check-in
            // 2. New checkout is before an existing checkout
            if (newCheckOut.isAfter(existingCheckIn) &&
                newCheckOut.isBefore(existingCheckOut)) {
              return true; // Conflict found
            }
          }
        }
      }

      return false; // No conflict
    } catch (e) {
      print('Error checking reservation conflict: $e');
      return true; // Assume conflict on error
    }
  }

  Future<void> _cancelReservation(
      String reservationId, Map<String, dynamic> reservation) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user.');
      }

      final String userId = user.uid;

      // Fetch the reservation data
      final reservationRef =
          FirebaseDatabase.instance.ref('reservations/$userId/$reservationId');
      final reservationSnapshot = await reservationRef.get();

      if (!reservationSnapshot.exists) {
        throw Exception('Reservation not found.');
      }

      // Move the reservation to the history node with status "Canceled"
      await FirebaseDatabase.instance
          .ref('history/$userId/$reservationId')
          .set({
        ...reservation,
        'status': 'Canceled', // Update the status to "Canceled"
      });

      // Remove the reservation from active reservations
      await reservationRef.remove();

      // Update the parking slot to remove the reservation
      final String slotId = reservation['slot'];
      await FirebaseDatabase.instance
          .ref('parkingSlots/$slotId/upcomingReservations/$reservationId')
          .remove();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation canceled successfully.')),
      );

      // Reload the active reservations
      setState(() {
        reservations.removeWhere((r) => r['id'] == reservationId);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error canceling reservation: $e')),
      );
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

  Widget _buildReservationCard(
      Map<String, dynamic> reservation, bool isActive) {
    String getReadableSlotName(String slotId) {
      return 'Slot ${slotId.replaceFirst('slot_', '').toUpperCase()}';
    }

    // Parse check-in time and date to determine if the reservation is active
    final DateTime? checkInTime = _parseDateTime(
      reservation['checkIn'],
      reservation['date'],
    );

    final DateTime now = DateTime.now();

    // Determine if the reservation is currently active
    final bool isActiveReservation = checkInTime != null &&
        now.year == checkInTime.year &&
        now.month == checkInTime.month &&
        now.day == checkInTime.day &&
        (now.isAfter(checkInTime) || now.isAtSameMomentAs(checkInTime));

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_parking, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  getReadableSlotName(reservation['slot']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.date_range, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Date: ${reservation['date']}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Time: ${reservation['checkIn']} - ${reservation['checkOut']}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showExtendDialog(
                    context,
                    reservation['id'],
                    reservation,
                  ),
                  icon: const Icon(Icons.timer, color: Colors.white),
                  label: const Text('Extend'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 16.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!isActiveReservation) // Show Cancel button only if not active
                  ElevatedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Confirm Cancel'),
                            content: const Text(
                                'Are you sure you want to cancel this reservation?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('No'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Yes'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirm == true) {
                        await _cancelReservation(
                            reservation['id'], reservation);
                      }
                    },
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12.0,
                        horizontal: 16.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Reservations'),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : reservations.isEmpty && regularCheckIn == null
              ? const Center(
                  child: Text(
                    'No active or upcoming reservations.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  itemCount: reservations.length,
                  itemBuilder: (context, index) {
                    final reservation = reservations[index];
                    final now = DateTime.now();

                    // Safely parse date and time
                    final checkInTime = _parseDateTime(
                      reservation['checkIn'],
                      reservation['date'],
                    );
                    final checkOutTime = _parseDateTime(
                      reservation['checkOut'],
                      reservation['date'],
                    );

                    // Check if both check-in and check-out times are valid
                    final isActive = (checkInTime != null &&
                        checkOutTime != null &&
                        now.isAfter(checkInTime) &&
                        now.isBefore(checkOutTime));

                    return _buildReservationCard(reservation, isActive);
                  },
                ),
      bottomNavigationBar: custom.NavigationBar(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushReplacementNamed(context, '/dashboard');
              break;
            case 1:
              Navigator.pushReplacementNamed(context, '/activeReservations');
              break;
            case 2:
              Navigator.pushReplacementNamed(context, '/scan');
              break;
            case 3:
              Navigator.pushReplacementNamed(context, '/history');
              break;
            case 4:
              Navigator.pushReplacementNamed(context, '/profile');
              break;
          }
        },
      ),
    );
  }
}
