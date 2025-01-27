import 'dart:async'; // Import for StreamSubscription
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'reservation_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapPage extends StatefulWidget {
  const MapPage({Key? key}) : super(key: key);

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late DatabaseReference dbRef;
  bool isLoading = true;
  Set<String> occupiedSlots = {}; // Fetched dynamically from Firebase
  final List<String> slotA = [
    'slot_A1',
    'slot_A2',
    'slot_A3',
    'slot_A4',
    'slot_A5',
    'slot_A6',
    'slot_A7'
  ];

  final List<String> slotB = [
    'slot_B1',
    'slot_B2',
    'slot_B3',
    'slot_B4',
    'slot_B5',
    'slot_B6',
    'slot_B7'
  ];

  StreamSubscription? slotSubscription; // Subscription to the Firebase listener

  @override
  void dispose() {
    slotSubscription
        ?.cancel(); // Cancel the subscription to prevent memory leaks
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Check if the user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('User is not authenticated');

      // Redirect to the login page if unauthenticated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      });
      return;
    }

    print('Authenticated user ID: ${user.uid}');

    // Proceed with setting up the Firebase listener
    dbRef = FirebaseDatabase.instance.ref('parkingSlots');
    _listenToSlotChanges();
  }

  void _listenToSlotChanges() {
    print('Listening to /parkingSlots...');
    slotSubscription = dbRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final Map<String, dynamic> data =
            Map<String, dynamic>.from(event.snapshot.value as Map);

        // Log data for debugging
        print('Fetched parkingSlots data: $data');

        // Extract occupied slots
        final Set<String> fetchedOccupiedSlots = data.entries
            .where((entry) => !(entry.value['isAvailable'] as bool))
            .map((entry) => entry.key)
            .toSet();

        setState(() {
          occupiedSlots = fetchedOccupiedSlots;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        print('No parkingSlots data available in Firebase.');
      }
    }, onError: (error) {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $error')),
      );
    });
  }

  // Build Legend Item
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  // Build Slots Overlay
  List<Widget> _buildSlotOverlay(
    List<String> slotA,
    List<String> slotB,
    Set<String> occupiedSlots,
    BuildContext context,
  ) {
    List<Widget> slots = [];

    // Add Slot A
    for (int i = 0; i < slotA.length; i++) {
      slots.add(
        Positioned(
          top: 73.5 + (i * 57.5), // Adjust top position dynamically
          left: 64.5, // Fixed left position for Slot A
          child: _buildSlot(slotA[i], occupiedSlots, context),
        ),
      );
    }

    // Add Slot B
    for (int i = 0; i < slotB.length; i++) {
      slots.add(
        Positioned(
          top: 132.0 + (i * 57.5), // Adjust top position dynamically
          left: 220.0, // Fixed left position for Slot B
          child: _buildSlot(slotB[i], occupiedSlots, context),
        ),
      );
    }

    return slots;
  }

  // Build a Single Slot Widget
  Widget _buildSlot(
      String slot, Set<String> occupiedSlots, BuildContext context) {
    final bool isOccupied = occupiedSlots.contains(slot);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReservationPage(selectedSlot: slot),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 100, // Adjust slot width
        height: 47.5, // Adjust slot height
        decoration: BoxDecoration(
          color: isOccupied ? Colors.red : Colors.green,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          slot.split('_').last, // Display slot name (e.g., A1, B1)
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking Lot Map'),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title and Legend
                  const Text(
                    'Parking Lot Overview',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Description about slot reservations
                  const Text(
                    'Tap on any slot to make a reservation. Slots marked in green are available, while red indicates occupied.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('Available', Colors.green),
                      const SizedBox(width: 16),
                      _buildLegendItem('Occupied', Colors.red),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Map with Slots Overlay
                  Expanded(
                    child: Stack(
                      children: [
                        // Map Image
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.5,
                            child: Image.asset(
                              'assets/images/parking_map.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                        // Slots Overlay
                        ..._buildSlotOverlay(
                            slotA, slotB, occupiedSlots, context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
