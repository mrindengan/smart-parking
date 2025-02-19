import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:smartparking/utils/admin_service.dart'; // Replace with your package name

class AdminParkingSlotsPage extends StatefulWidget {
  const AdminParkingSlotsPage({Key? key}) : super(key: key);

  @override
  _AdminParkingSlotsPageState createState() => _AdminParkingSlotsPageState();
}

class _AdminParkingSlotsPageState extends State<AdminParkingSlotsPage> {
  final DatabaseReference _slotsRef =
      FirebaseDatabase.instance.ref('parkingSlots');
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    final maroon = const Color(0xFF800000);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Parking Slots'),
        backgroundColor: maroon,
      ),
      body: StreamBuilder(
        stream: _slotsRef.onValue,
        builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text('No parking slot data found.'));
          }

          final data = snapshot.data!.snapshot.value as Map;
          List<SlotItem> slots = [];
          data.forEach((slotId, slotData) {
            final Map slotMap = slotData as Map;
            slots.add(
              SlotItem(
                slotId: slotId.toString(),
                isAvailable: slotMap['isAvailable'] ?? true,
                databaseChangeTime:
                    slotMap['databaseChangeTime']?.toString() ?? 'N/A',
              ),
            );
          });

          // Sort slots alphabetically by slotId
          slots.sort((a, b) => a.slotId.compareTo(b.slotId));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              // Remove prefix "slot_" for display
              final displaySlotId = slot.slotId.replaceAll('slot_', '');
              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                slot.isAvailable ? Colors.green : Colors.red,
                            radius: 24,
                            child: Text(
                              displaySlotId,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Slot: $displaySlotId',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('Available: ${slot.isAvailable}',
                                    style: const TextStyle(fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('Updated: ${slot.databaseChangeTime}',
                                    style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                await _adminService.updateParkingSlotStatus(
                                  slot.slotId,
                                  !slot.isAvailable,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Slot $displaySlotId updated.')),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error updating slot: $e')),
                                );
                              }
                            },
                            child: Text(slot.isAvailable
                                ? 'Mark Unavailable'
                                : 'Mark Available'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: maroon,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
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

class SlotItem {
  final String slotId;
  final bool isAvailable;
  final String databaseChangeTime;

  SlotItem({
    required this.slotId,
    required this.isAvailable,
    required this.databaseChangeTime,
  });
}
