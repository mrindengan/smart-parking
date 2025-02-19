import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:smartparking/utils/admin_service.dart'; // Replace with your package name

class AdminReservationsPage extends StatefulWidget {
  const AdminReservationsPage({Key? key}) : super(key: key);

  @override
  _AdminReservationsPageState createState() => _AdminReservationsPageState();
}

class _AdminReservationsPageState extends State<AdminReservationsPage> {
  final DatabaseReference _reservationsRef =
      FirebaseDatabase.instance.ref('reservations');
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    final maroon = const Color(0xFF800000);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Reservations'),
        backgroundColor: maroon,
      ),
      body: StreamBuilder(
        stream: _reservationsRef.onValue,
        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text('No reservations found.'));
          }

          final Map data = snapshot.data!.snapshot.value as Map;
          List<ReservationItem> reservationsList = [];

          data.forEach((userId, userReservations) {
            final Map resMap = userReservations as Map;
            resMap.forEach((reservationId, reservationData) {
              final Map res = reservationData as Map;
              // Parse slot data to remove "slot_" prefix
              final displaySlot = res['slot'] != null
                  ? res['slot'].toString().replaceAll('slot_', '')
                  : '';
              // Use username if available, otherwise fallback to userId
              final username = res['username'] ?? userId.toString();
              reservationsList.add(
                ReservationItem(
                  username: username,
                  reservationId: reservationId.toString(),
                  slot: displaySlot,
                  checkIn: res['checkIn'] ?? '',
                  checkOut: res['checkOut'] ?? '',
                  status: res['status'] ?? '',
                ),
              );
            });
          });

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: reservationsList.length,
            itemBuilder: (context, index) {
              final reservation = reservationsList[index];
              Color statusColor;
              if (reservation.status.toLowerCase() == 'canceled') {
                statusColor = Colors.red;
              } else if (reservation.status.toLowerCase() == 'checkedin') {
                statusColor = Colors.green;
              } else {
                statusColor = maroon;
              }
              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Username: ${reservation.username}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Slot: ${reservation.slot}',
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Check-In: ${reservation.checkIn}',
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Check-Out: ${reservation.checkOut}',
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('Status: ',
                              style: TextStyle(fontSize: 14)),
                          Chip(
                            label: Text(reservation.status,
                                style: const TextStyle(color: Colors.white)),
                            backgroundColor: statusColor,
                          ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              TimeOfDay? selectedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (selectedTime != null) {
                                final formattedTime =
                                    selectedTime.format(context);
                                try {
                                  await _adminService.extendReservation(
                                    reservation.username,
                                    reservation.reservationId,
                                    formattedTime,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Reservation extended.')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                            icon: Icon(Icons.timer,
                                size: 28, color: Colors.white),
                            label: const Text('Extend'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: maroon,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 24),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              bool? confirm = await showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Cancel Reservation'),
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
                                ),
                              );
                              if (confirm == true) {
                                try {
                                  await _adminService.cancelReservation(
                                    reservation.username,
                                    reservation.reservationId,
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Reservation canceled.')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                            icon: Icon(Icons.cancel,
                                size: 28, color: Colors.white),
                            label: const Text('Cancel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: maroon,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 24),
                              textStyle: const TextStyle(fontSize: 16),
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
            },
          );
        },
      ),
    );
  }
}

class ReservationItem {
  final String username;
  final String reservationId;
  final String slot;
  final String checkIn;
  final String checkOut;
  final String status;

  ReservationItem({
    required this.username,
    required this.reservationId,
    required this.slot,
    required this.checkIn,
    required this.checkOut,
    required this.status,
  });
}
