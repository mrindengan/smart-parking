import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:smartparking/utils/app_state.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../widgets/navigation_bar.dart' as custom;

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late AppState appState; // Access AppState dynamically using Provider.
  User? currentUser;
  String? email;
  String? name;
  String? phoneNumber;
  File? profileImage;
  String? studentId;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    currentUser = _auth.currentUser;
    email = currentUser?.email;
    _fetchUserData();
    Provider.of<AppState>(context, listen: false);
    // Load the profile image on initialization
  }

  Future<bool> requestMediaPermission() async {
    if (Platform.isAndroid) {
      if (await Permission.photos.isDenied) {
        final photoPermission = await Permission.photos.request();
        if (photoPermission.isGranted) return true;
      }

      if (await Permission.mediaLibrary.isDenied) {
        final mediaPermission = await Permission.mediaLibrary.request();
        if (mediaPermission.isGranted) return true;
      }

      // If permissions are neither granted nor requested
      return await Permission.photos.isGranted ||
          await Permission.mediaLibrary.isGranted;
    }

    if (Platform.isIOS) {
      final photoPermission = await Permission.photos.request();
      return photoPermission.isGranted;
    }

    return true; // Other platforms (e.g., Web)
  }

  void _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully logged out!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during logout: $e')),
      );
    }
  }

  Future<void> _fetchUserData() async {
    if (currentUser == null) return;

    final userId = currentUser!.uid;
    final snapshot = await _dbRef.child('users/$userId').get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      setState(() {
        name = data['name'];
        phoneNumber = data['phoneNumber'];
        studentId = data['studentId'];
      });
    }
  }

  Future<String?> _showEditDialog(String field, String currentValue) async {
    String newValue = currentValue;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $field'),
          content: TextField(
            onChanged: (value) => newValue = value,
            controller: TextEditingController(text: currentValue),
            decoration: InputDecoration(
              hintText: 'Enter your $field',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(newValue),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateUserData(String key, String value) async {
    if (currentUser == null) return;

    try {
      final userId = currentUser!.uid;
      await _dbRef.child('users/$userId').update({key: value});

      // Update the local state after a successful database update
      setState(() {
        if (key == 'name') name = value;
        if (key == 'phoneNumber') phoneNumber = value;
        if (key == 'studentId') studentId = value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    }
  }

  Widget _buildProfileField(String label, String? value, String? key,
      {bool editable = true, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value ?? 'Not available',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          if (editable)
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
              onPressed: () async {
                final newValue = await _showEditDialog(label, value ?? '');
                if (newValue != null && newValue.isNotEmpty) {
                  await _updateUserData(key!, newValue);
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Page'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Picture
            Stack(
              alignment: Alignment.center,
              children: [
                StreamBuilder<File?>(
                  stream: appState.profileImageStream,
                  builder: (context, snapshot) {
                    return CircleAvatar(
                      radius: 70,
                      backgroundColor: Colors.blue.shade100,
                      backgroundImage: const AssetImage(
                        'assets/images/profile_placeholder.png',
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Tap to change profile picture',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // Profile Information
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileField('Name', name, 'name',
                        icon: FontAwesomeIcons.user),
                    const Divider(thickness: 1, height: 16),
                    _buildProfileField(
                        'Phone Number', phoneNumber, 'phoneNumber',
                        icon: FontAwesomeIcons.phone),
                    const Divider(thickness: 1, height: 16),
                    _buildProfileField('Student ID', studentId, 'studentId',
                        icon: FontAwesomeIcons.idCard),
                    const Divider(thickness: 1, height: 16),
                    _buildProfileField('Email', email, null,
                        editable: false, icon: FontAwesomeIcons.envelope),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  'Logout',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: custom.NavigationBar(
        currentIndex: 4,
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
