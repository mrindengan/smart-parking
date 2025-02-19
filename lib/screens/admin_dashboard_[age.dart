import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({Key? key}) : super(key: key);

  @override
  _AdminDashboardPageState createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  int totalReservations = 0;
  int totalParkingSlots = 0;
  int availableParkingSlots = 0;
  int totalUsers = 0;

  @override
  void initState() {
    super.initState();
    _listenToStatistics();
  }

  void _listenToStatistics() {
    _dbRef.child('reservations').onValue.listen((event) {
      int count = 0;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        data.forEach((userId, reservations) {
          if (reservations is Map) {
            count += reservations.length;
          }
        });
      }
      setState(() {
        totalReservations = count;
      });
    });

    _dbRef.child('parkingSlots').onValue.listen((event) {
      int total = 0;
      int available = 0;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        total = data.length;
        data.forEach((key, value) {
          if (value is Map && value['isAvailable'] == true) {
            available++;
          }
        });
      }
      setState(() {
        totalParkingSlots = total;
        availableParkingSlots = available;
      });
    });

    _dbRef.child('users').onValue.listen((event) {
      int count = 0;
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map;
        count = data.length;
      }
      setState(() {
        totalUsers = count;
      });
    });
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(8),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.7), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 18, color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentHistorySection() {
    final maroon = const Color(0xFF800000);
    return StreamBuilder(
      stream: _dbRef.child('history').onValue,
      builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text('No recent history.'));
        }
        final Map historyData = snapshot.data!.snapshot.value as Map;
        List<Map> allEntries = [];
        historyData.forEach((userId, userHistory) {
          if (userHistory is Map) {
            userHistory.forEach((historyId, entry) {
              if (entry is Map) {
                entry['userId'] = userId;
                allEntries.add(entry);
              }
            });
          }
        });
        allEntries.sort((a, b) {
          int timeA =
              a['databaseChangeTime'] is int ? a['databaseChangeTime'] : 0;
          int timeB =
              b['databaseChangeTime'] is int ? b['databaseChangeTime'] : 0;
          return timeB.compareTo(timeA);
        });
        final recentEntries = allEntries.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent History',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: maroon,
              ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentEntries.length,
              itemBuilder: (context, index) {
                final entry = recentEntries[index];
                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(Icons.history, color: maroon, size: 32),
                    title: Text('User: ${entry['userId']}',
                        style: const TextStyle(fontSize: 16)),
                    subtitle: Text(
                      'Status: ${entry['status'] ?? 'N/A'}\nUpdated: ${entry['databaseChangeTime'] ?? 'N/A'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final maroon = const Color(0xFF800000);
    final screenHeight = MediaQuery.of(context).size.height -
        kToolbarHeight -
        MediaQuery.of(context).padding.top;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: maroon,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 28),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: screenHeight * 0.65,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Welcome, Admin!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: maroon,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildStatCard(
                          "Reservations", totalReservations.toString(), maroon),
                      _buildStatCard(
                          "Total Slots", totalParkingSlots.toString(), maroon),
                      _buildStatCard("Available",
                          availableParkingSlots.toString(), maroon),
                      _buildStatCard("Users", totalUsers.toString(), maroon),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/adminReservations');
                          },
                          icon: Icon(Icons.receipt_long,
                              size: 28, color: Colors.white),
                          label: const Text('Reservations'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: maroon,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 24),
                            textStyle: const TextStyle(fontSize: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pushNamed(context, '/adminParkingSlots');
                          },
                          icon: Icon(Icons.local_parking,
                              size: 28, color: Colors.white),
                          label: const Text('Parking Slots'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: maroon,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 24),
                            textStyle: const TextStyle(fontSize: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  child: _buildRecentHistorySection(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
