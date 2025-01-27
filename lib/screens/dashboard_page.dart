import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/navigation_bar.dart' as custom;

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? activeReservation; // Holds active reservation details
  int availableSlots = 0;
  String? firstName = 'user';
  int occupiedSlots = 0;
  File? profileImage;
  bool showNotification = true; // Controls the notification banner visibility
  int totalSlots = 0;

  @override
  void initState() {
    super.initState();
    _listenToActiveReservation();
    _listenToSlotData();
    _listenToUserName();
    _listenToUserInfo();
    _loadProfileImage();
  }

  void _listenToUserName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final dbRef = FirebaseDatabase.instance.ref('users/$userId');

    dbRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final fullName = (data['name'] as String?)?.trim() ?? 'User';

        if (fullName.isEmpty) {
          setState(() {
            firstName = 'User';
          });
          print('Name is empty. Defaulting to "User".');
        } else {
          setState(() {
            firstName = fullName.split(' ').first;
          });
          print('User name updated: $firstName');
        }
      } else {
        setState(() {
          firstName = 'User';
        });
        print('User name not found in snapshot.');
      }
    });
  }

  void _listenToUserInfo() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final userRef = FirebaseDatabase.instance.ref('users/$userId');

    userRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final userData = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          firstName = userData['name']?.split(' ').first ?? 'User';

          // Explicitly clear activeReservation when isCheckedIn is false
          if (userData['isCheckedIn'] == true &&
              userData['currentSlot'] != null) {
            activeReservation = {
              'slot': userData['currentSlot'],
              'status': 'CheckedIn',
            };
          } else {
            activeReservation = null; // Clear active reservation
          }
        });
      } else {
        setState(() {
          firstName = 'User'; // Default name
          activeReservation = null; // Clear active reservation
        });
      }
    });
  }

  Future<void> _loadProfileImage() async {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/profile_image.png';
    final file = File(filePath);
    if (await file.exists()) {
      setState(() {
        profileImage = file;
      });
    }
  }

  void _listenToActiveReservation() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final dbRef = FirebaseDatabase.instance.ref();

    // Listen to reservations
    dbRef.child('reservations/$userId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final reservations =
            Map<String, dynamic>.from(event.snapshot.value as Map);

        final now = DateTime.now();
        Map<String, dynamic>? active;
        Map<String, dynamic>? upcoming;

        for (final entry in reservations.entries) {
          final reservation = Map<String, dynamic>.from(entry.value);

          // Safely parse DateTime and handle null
          final checkInTime =
              _parseDateTime(reservation['checkIn'], reservation['date']);
          final checkOutTime =
              _parseDateTime(reservation['checkOut'], reservation['date']);

          if (checkInTime != null && checkOutTime != null) {
            if (now.isAfter(checkInTime) && now.isBefore(checkOutTime)) {
              active = reservation;
              break; // Stop processing if an active reservation is found
            } else if (now.isBefore(checkInTime)) {
              if (upcoming == null ||
                  (upcoming['checkIn'] != null &&
                      _parseDateTime(upcoming['checkIn'], upcoming['date']) !=
                          null &&
                      checkInTime.isBefore(_parseDateTime(
                          upcoming['checkIn'], upcoming['date'])!))) {
                upcoming = reservation;
              }
            }
          } else {
            print('Debug: Null DateTime encountered in reservation. Skipping.');
          }
        }

        setState(() {
          activeReservation = active ?? upcoming;
        });
      } else {
        setState(() {
          activeReservation = null;
        });
      }
    });

    // Listen to regular check-in status
    dbRef.child('users/$userId').onValue.listen((event) {
      if (event.snapshot.exists) {
        final userData = Map<String, dynamic>.from(event.snapshot.value as Map);

        if (userData['isCheckedIn'] == true &&
            userData['currentSlot'] != null) {
          setState(() {
            activeReservation = {
              'slot': userData['currentSlot'],
              'status': 'Checked In',
            };
          });
        } else if (activeReservation == null) {
          setState(() {
            activeReservation = null; // Clear if no reservation or check-in
          });
        }
      }
    });
  }

  void _listenToSlotData() {
    final dbRef = FirebaseDatabase.instance.ref('parkingSlots');

    dbRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final slots = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          totalSlots = slots.length;
          availableSlots =
              slots.values.where((slot) => slot['isAvailable'] == true).length;
          occupiedSlots = totalSlots - availableSlots;
        });
      }
    });
  }

  bool _shouldShowNotification() {
    if (activeReservation == null) return false;

    try {
      // Parse check-out time from the active reservation
      final checkOutTime = _parseDateTime(
        activeReservation!['checkOut'] as String?,
        activeReservation!['date'] as String?,
      );

      if (checkOutTime == null) {
        print('Debug: checkOutTime is null. Skipping notification.');
        return false; // If checkOutTime is null, no notification should be shown
      }

      // Get the current time
      final currentTime = DateTime.now();

      // Calculate the time difference
      final timeRemaining = checkOutTime.difference(currentTime);

      // Show notification only if:
      // 1. The current time is before the check-out time
      // 2. The check-out time is within the next 30 minutes
      return currentTime.isBefore(checkOutTime) &&
          timeRemaining.inMinutes <= 30;
    } catch (e) {
      // Handle any parsing errors gracefully
      print('Error parsing reservation time: $e');
      return false;
    }
  }

  Widget _buildNotificationBanner(String message) {
    return Card(
      color: Colors.amber[300],
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: const Icon(Icons.notifications_active, color: Colors.black),
        title: const Text(
          'Reservation Reminder',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(message),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () {
            setState(() {
              showNotification = false; // Collapse the notification
            });
          },
        ),
      ),
    );
  }

  String _getReadableSlotName(String slotId) {
    return slotId.split('_').last;
  }

  DateTime? _parseDateTime(String? time, String? date) {
    if (time == null || date == null) {
      print('Debug: Invalid time or date. Returning null.');
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
      print('Error parsing date or time: $e');
      return null;
    }
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Expanded(
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 36),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Parking Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notification Banner
            if (showNotification && _shouldShowNotification())
              _buildNotificationBanner(
                'Slot ${_getReadableSlotName(activeReservation!['slot'])}: Your reservation will end soon. Please extend or prepare to check out.',
              ),

            const SizedBox(height: 16),

            // User Info Section
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Profile Picture
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.teal,
                      child: CircleAvatar(
                        radius: 35,
                        backgroundImage: const AssetImage(
                          'assets/images/profile_placeholder.png',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // User Info and Active Reservation/Check-In Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Welcome Message
                          Text(
                            firstName != null && firstName!.isNotEmpty
                                ? 'Welcome back, $firstName!'
                                : 'Welcome back!',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Active or Upcoming Reservation/Check-In Details
                          activeReservation != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeReservation!['status'] ==
                                              'CheckedIn'
                                          ? 'Checked-In:' // Regular user check-in
                                          : 'Active Reservation:', // Reserved user with active reservation
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Slot: ${_getReadableSlotName(activeReservation!['slot'])}',
                                    ),
                                    if (activeReservation!['status'] !=
                                        'CheckedIn') ...[
                                      if (activeReservation!['date'] != null)
                                        Text(
                                            'Date: ${activeReservation!['date']}'),
                                      if (activeReservation!['checkIn'] !=
                                              null &&
                                          activeReservation!['checkOut'] !=
                                              null)
                                        Text(
                                          'Time: ${activeReservation!['checkIn']} - ${activeReservation!['checkOut']}',
                                        ),
                                    ],
                                  ],
                                )
                              : const Text(
                                  'You have no active reservations or check-ins.',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Metrics Section
            const Text(
              'Overview',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildMetricCard(
                  title: 'Total Slots',
                  value: totalSlots.toString(),
                  color: Colors.teal,
                  icon: Icons.directions_car,
                ),
                _buildMetricCard(
                  title: 'Available',
                  value: availableSlots.toString(),
                  color: Colors.green,
                  icon: Icons.check_circle,
                ),
                _buildMetricCard(
                  title: 'Occupied',
                  value: occupiedSlots.toString(),
                  color: Colors.red,
                  icon: Icons.cancel,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Reserve Now Button
            Center(
              child: SizedBox(
                width:
                    double.infinity, // Ensures the button spans the full width
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/map');
                  },
                  icon: const Icon(
                    Icons.map,
                    size: 28, // Increased icon size
                    color: Colors
                        .white, // Matches the button text color for better contrast
                  ),
                  label: const Text(
                    'Reserve Now',
                    style: TextStyle(
                      fontSize: 20, // Slightly larger font size
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20.0), // Increased padding
                    backgroundColor: Colors.teal, // Button background color
                    foregroundColor: Colors.white, // Text color
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12), // Rounded corners
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Occupancy Progress Section
            const Text(
              'Occupancy Progress',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Occupancy Status'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: totalSlots > 0 ? occupiedSlots / totalSlots : 0,
                      backgroundColor: Colors.green[100],
                      color: Colors.red,
                      minHeight: 10,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Available'),
                        Text(
                          '$occupiedSlots Occupied / $totalSlots Total',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: custom.NavigationBar(
        currentIndex: 0,
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
