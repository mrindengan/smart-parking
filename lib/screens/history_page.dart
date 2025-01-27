import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/navigation_bar.dart' as custom;

class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  List<Map<String, dynamic>> reservationHistory = [];
  List<Map<String, dynamic>> regularCheckOutHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToHistory();
  }

  void _listenToHistory() {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    _dbRef.child('history/$userId').onValue.listen((event) {
      if (!event.snapshot.exists) {
        setState(() {
          reservationHistory = [];
          regularCheckOutHistory = [];
          isLoading = false;
        });
        return;
      }

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);

      List<Map<String, dynamic>> reservationHistoryTemp = [];
      List<Map<String, dynamic>> regularCheckOutHistoryTemp = [];

      data.forEach((key, value) {
        final entry = Map<String, dynamic>.from(value);

        if (entry.containsKey('checkIn')) {
          // Reservation-related history
          reservationHistoryTemp.add({...entry, 'id': key});
        } else if (entry.containsKey('slot') && entry.containsKey('checkOut')) {
          // Regular check-out history
          regularCheckOutHistoryTemp.add({...entry, 'id': key});
        }
      });

      // Sort reservations by most recent activity
      reservationHistoryTemp.sort((a, b) {
        DateTime dateA, dateB;

        try {
          dateA = _parseDateTime(a['checkOut'], a['date']) ??
              DateTime.parse(a['checkIn']);
        } catch (e) {
          print('Error parsing dateA: $e');
          dateA = DateTime.fromMillisecondsSinceEpoch(0); // Default fallback
        }

        try {
          dateB = _parseDateTime(b['checkOut'], b['date']) ??
              DateTime.parse(b['checkIn']);
        } catch (e) {
          print('Error parsing dateB: $e');
          dateB = DateTime.fromMillisecondsSinceEpoch(0); // Default fallback
        }

        return dateB.compareTo(dateA);
      });

      // Sort regular check-outs by check-out time
      regularCheckOutHistoryTemp.sort((a, b) {
        final dateA = DateTime.parse(a['checkOut']);
        final dateB = DateTime.parse(b['checkOut']);
        return dateB.compareTo(dateA);
      });

      setState(() {
        reservationHistory = reservationHistoryTemp;
        regularCheckOutHistory = regularCheckOutHistoryTemp;
        isLoading = false;
      });
    });
  }

  DateTime? _parseDateTime(String? time, String? date) {
    if (time == null || date == null) {
      print('DEBUG: Invalid time or date. Returning null.');
      return null;
    }

    try {
      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1].split(' ')[0]);
      final isPM = time.contains('PM');
      final dateParts = date.split('-'); // Format: DD-MM-YYYY

      return DateTime(
        int.parse(dateParts[2]), // Year
        int.parse(dateParts[1]), // Month
        int.parse(dateParts[0]), // Day
        isPM ? (hour % 12) + 12 : hour,
        minute,
      );
    } catch (e) {
      print('DEBUG: Error parsing DateTime: $e');
      return null; // Return null on error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reservationHistory.isNotEmpty) ...[
                    const Text(
                      'Reservation History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...reservationHistory
                        .map((history) => _buildReservationCard(history)),
                  ],
                  if (regularCheckOutHistory.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Regular Check-In/Check-Out History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...regularCheckOutHistory
                        .map((history) => _buildRegularCheckOutCard(history)),
                  ],
                  if (reservationHistory.isEmpty &&
                      regularCheckOutHistory.isEmpty)
                    const Center(child: Text('No history records found.')),
                ],
              ),
            ),
      bottomNavigationBar: custom.NavigationBar(
        currentIndex: 3,
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

  Widget _buildReservationCard(Map<String, dynamic> history) {
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
                const FaIcon(FontAwesomeIcons.calendar, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Date: ${history['date']}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.parking,
                    color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  'Slot: ${_getReadableSlotName(history['slot'])}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (history['checkIn'] != null && history['checkOut'] != null)
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Time: ${history['checkIn']} - ${history['checkOut']}',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.timer, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Duration: ${history['duration'] ?? 'N/A'}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildStatusTag(history['status']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegularCheckOutCard(Map<String, dynamic> history) {
    final DateTime checkOutTime = DateTime.parse(history['checkOut']);
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
                const FaIcon(FontAwesomeIcons.calendarCheck,
                    color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Check-Out: ${_formatDateTime(checkOutTime)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                const Icon(Icons.local_parking, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Slot: ${_getReadableSlotName(history['slot'])}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildStatusTag(history['status']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}-${dateTime.month}-${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }

  Widget _buildStatusTag(String status) {
    final statusColor = status == 'CheckedOut' ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        border: Border.all(color: statusColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: statusColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getReadableSlotName(String slotId) {
    return slotId.split('_').last; // Example: slot_B7 -> B7
  }
}
