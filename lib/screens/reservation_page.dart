import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ReservationPage extends StatefulWidget {
  const ReservationPage({Key? key, required this.selectedSlot})
      : super(key: key);

  final String selectedSlot; // Pre-filled slot from Map Page

  @override
  _ReservationPageState createState() => _ReservationPageState();
}

class _ReservationPageState extends State<ReservationPage> {
  TimeOfDay? checkInTime;
  TimeOfDay? checkOutTime;
  Duration? parkingDuration;
  DateTime? selectedDate;

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now(); // Current date and time
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now, // Restrict to today or later
      lastDate: now.add(const Duration(days: 7)), // Limit to one week
    );
    if (date != null) {
      setState(() {
        selectedDate = date;
      });
    }
  }

  Future<void> _pickTime({required bool isCheckIn}) async {
    final TimeOfDay now = TimeOfDay.now(); // Current time
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: now, // Start at current time
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (time != null) {
      // Ensure the selected time is not in the past
      final DateTime fullSelectedDate = DateTime(
        selectedDate?.year ?? DateTime.now().year,
        selectedDate?.month ?? DateTime.now().month,
        selectedDate?.day ?? DateTime.now().day,
        time.hour,
        time.minute,
      );

      if (fullSelectedDate.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a valid time.')),
        );
        return;
      }

      if (time.hour < 5 || time.hour > 21) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Please select a time between 5:00 AM and 9:00 PM')),
        );
        return;
      }

      setState(() {
        if (isCheckIn) {
          checkInTime = time;
        } else {
          checkOutTime = time;
        }
        _calculateDuration();
      });
    }
  }

  void _calculateDuration() {
    if (checkInTime != null && checkOutTime != null) {
      final checkInDateTime = DateTime(
        selectedDate?.year ?? DateTime.now().year,
        selectedDate?.month ?? DateTime.now().month,
        selectedDate?.day ?? DateTime.now().day,
        checkInTime!.hour,
        checkInTime!.minute,
      );
      final checkOutDateTime = DateTime(
        selectedDate?.year ?? DateTime.now().year,
        selectedDate?.month ?? DateTime.now().month,
        selectedDate?.day ?? DateTime.now().day,
        checkOutTime!.hour,
        checkOutTime!.minute,
      );

      if (checkOutDateTime.isAfter(checkInDateTime)) {
        setState(() {
          parkingDuration = checkOutDateTime.difference(checkInDateTime);
        });
      } else {
        setState(() {
          parkingDuration = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Check-out time must be later than check-in time.')),
        );
      }
    }
  }

  Future<void> _saveReservation() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No authenticated user.');
      }

      final String userId = user.uid;
      final String formattedDate =
          '${selectedDate!.day.toString().padLeft(2, '0')}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.year}';

      final DatabaseReference dbRef =
          FirebaseDatabase.instance.ref('reservations/$userId').push();
      final String reservationId = dbRef.key!;

      final reservationData = {
        'id': reservationId,
        'slot': widget.selectedSlot,
        'date': formattedDate,
        'checkIn': checkInTime!.format(context),
        'checkOut': checkOutTime!.format(context),
        'duration':
            '${parkingDuration!.inHours}h ${parkingDuration!.inMinutes % 60}m',
        'status': 'Reserved',
      };

      // Check for conflicts with existing reservations for the same slot
      final slotRef =
          FirebaseDatabase.instance.ref('parkingSlots/${widget.selectedSlot}');
      final slotSnapshot = await slotRef.child('upcomingReservations').get();

      if (slotSnapshot.exists) {
        final Map<String, dynamic> upcomingReservations =
            Map<String, dynamic>.from(slotSnapshot.value as Map);

        for (final reservation in upcomingReservations.values) {
          final String reservationDate = reservation['date'] ?? '';
          final String reservationCheckIn = reservation['checkIn'] ?? '';
          final String reservationCheckOut = reservation['checkOut'] ?? '';

          final DateTime existingCheckIn =
              _parseDateTime(reservationCheckIn, reservationDate);
          final DateTime existingCheckOut =
              _parseDateTime(reservationCheckOut, reservationDate);

          final DateTime newCheckIn =
              _parseDateTime(reservationData['checkIn']!, formattedDate);
          final DateTime newCheckOut =
              _parseDateTime(reservationData['checkOut']!, formattedDate);

          // Check for overlap
          if (!(newCheckOut.isBefore(existingCheckIn) ||
              newCheckIn.isAfter(existingCheckOut))) {
            // Conflict detected
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'Conflict: The slot is reserved from ${reservationCheckIn} to ${reservationCheckOut} on $reservationDate. Please select a different time.'),
              ),
            );
            return; // Stop further processing
          }
        }
      }

      // Save reservation under user node
      await dbRef.set(reservationData);

      // Add to the slot's upcomingReservations
      await slotRef.child('upcomingReservations/$reservationId').set({
        'userId': userId,
        'checkIn': reservationData['checkIn'],
        'checkOut': reservationData['checkOut'],
        'date': reservationData['date'],
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation saved successfully!')),
      );

      Navigator.of(context)
          .pushNamedAndRemoveUntil('/dashboard', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving reservation: $e')),
      );
    }
  }

  DateTime _parseDateTime(String time, String date) {
    final dateParts = date.split('-'); // Format: DD-MM-YYYY
    final timeParts = time.split(' '); // Format: HH:MM AM/PM
    final hourMinute = timeParts[0].split(':');
    final hour = int.parse(hourMinute[0]);
    final minute = int.parse(hourMinute[1]);
    final isPM = timeParts[1] == 'PM';

    return DateTime(
      int.parse(dateParts[2]), // Year
      int.parse(dateParts[1]), // Month
      int.parse(dateParts[0]), // Day
      isPM ? (hour % 12) + 12 : hour,
      minute,
    );
  }

  void _showConfirmationDialog() {
    if (selectedDate == null ||
        checkInTime == null ||
        checkOutTime == null ||
        parkingDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields')),
      );
      return;
    }

    // Format the date to "Day, DD-MM-YYYY"
    final String formattedDate =
        '${_getDayName(selectedDate!.weekday)}, ${selectedDate!.day.toString().padLeft(2, '0')}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.year}';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reservation Confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slot: ${_getReadableSlotName(widget.selectedSlot)}'),
            Text('Date: $formattedDate'),
            Text('Check-In: ${checkInTime!.format(context)}'),
            Text('Check-Out: ${checkOutTime!.format(context)}'),
            Text(
                'Duration: ${parkingDuration!.inHours} hours ${parkingDuration!.inMinutes % 60} minutes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _saveReservation(); // Save reservation
            },
            child: const Text('Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];
    return days[weekday % 7];
  }

  String _getReadableSlotName(String slotId) {
    return slotId.split('_').last; // Converts 'slot_B4' to 'B4'
  }

  @override
  Widget build(BuildContext context) {
    String _getReadableSlotName(String slotId) {
      return 'Slot ${slotId.replaceFirst('slot_', '').toUpperCase()}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reserve a Slot'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slot Display
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
                    // Selected Slot Row
                    Row(
                      children: [
                        const Icon(Icons.local_parking,
                            color: Colors.teal, size: 40),
                        const SizedBox(width: 16),
                        Text(
                          'Selected Slot: ${_getReadableSlotName(widget.selectedSlot)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const Divider(
                      height: 20,
                      thickness: 2,
                      color: Colors.grey,
                    ), // Divider between slot info and working hours

                    // Working Time Info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Our service operates from 5:00 AM to 10:00 PM. Please select a reservation time within this working period.',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date Selection
            const Text(
              'Select Date',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDate,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.teal),
                      const SizedBox(width: 16),
                      Text(
                        selectedDate == null
                            ? 'Choose Date'
                            : '${selectedDate!.toLocal()}'.split(' ')[0],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time Selection
            const Text(
              'Select Check-In and Check-Out Times',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickTime(isCheckIn: true),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.teal),
                      const SizedBox(width: 16),
                      Text(
                        checkInTime == null
                            ? 'Choose Check-In Time'
                            : checkInTime!.format(context),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickTime(isCheckIn: false),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.teal),
                      const SizedBox(width: 16),
                      Text(
                        checkOutTime == null
                            ? 'Choose Check-Out Time'
                            : checkOutTime!.format(context),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Confirm Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showConfirmationDialog,
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Confirm Reservation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
