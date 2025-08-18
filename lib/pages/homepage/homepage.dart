import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 1;

  // Firestore data
  String? plateNumber;
  String? make;
  String? modelFamily;
  int? modelYear;
  String? variant;
  String? location;
  String? serviceStatus;
  String? upcomingAppointment;

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 🔹 Step 1: Get Firestore data as before...
      final ownerDoc =
          await FirebaseFirestore.instance
              .collection('car_owners')
              .doc(user.uid)
              .get();
      final activeVehicleId = ownerDoc.data()?['activeVehicleId'];

      if (activeVehicleId != null) {
        final vehicleDoc =
            await FirebaseFirestore.instance
                .collection('vehicles')
                .doc(activeVehicleId)
                .get();
        if (vehicleDoc.exists) {
          final vData = vehicleDoc.data()!;
          plateNumber = vData['plateNumber'];
          make = vData['make'];
          modelFamily = vData['modelFamily'];
          modelYear = vData['modelYear'];
          variant = vData['variant'];
        }
      }

      // 🔹 Step 2: Get latest service appointment
      final appointmentsSnap =
          await FirebaseFirestore.instance
              .collection('serviceAppointments')
              .where('ownerId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .limit(1)
              .get();

      if (appointmentsSnap.docs.isNotEmpty) {
        final appt = appointmentsSnap.docs.first.data();
        serviceStatus = appt['status'] ?? 'No Appointment Made Yet...';
        if (appt['upcomingDate'] != null) {
          final ts = appt['upcomingDate'] as Timestamp;
          upcomingAppointment =
              '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}';
        } else {
          upcomingAppointment = 'No Appointment Made Yet...';
        }
      } else {
        serviceStatus = 'No Appointment Made Yet...';
        upcomingAppointment = 'No Appointment Made Yet...';
      }

      // 🔹 Step 3: Get current GPS location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          location = 'Location permission denied';
          setState(() => loading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        location = 'Location permission permanently denied';
        setState(() => loading = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 🔹 Step 4: Reverse geocoding to address
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        location = "${place.locality}, ${place.administrativeArea}";
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
    }

    setState(() => loading = false);
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Add navigation logic if needed
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoMate'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'My Vehicle',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.message),
            label: 'Direct Message',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // === CAR INFO & LOCATION ===
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      make != null
                          ? Image.network(
                            'https://cdn.imagin.studio/getImage?customer=demo&make=$make&modelFamily=$modelFamily&modelYear=$modelYear&angle=01',
                            height: 80,
                            width: 120,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            height: 80,
                            width: 120,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.directions_car, size: 40),
                          ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plate: ${plateNumber ?? "Plate number is loading..."}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('$make $modelFamily $variant'),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(location ?? 'Location is loading...'),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Change My Vehicle',
                  onPressed: () {},
                ),
              ],
            ),

            const SizedBox(height: 20),

            // === FEATURE BUTTONS ===
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _buildFeatureButton(
                  Icons.home_repair_service,
                  'Workshop',
                  () {},
                ),
                _buildFeatureButton(
                  Icons.miscellaneous_services,
                  'Services',
                  () {},
                ),
                _buildFeatureButton(Icons.car_crash, 'Towing', () {}),
                _buildFeatureButton(Icons.history, 'Service History', () {}),
                _buildFeatureButton(Icons.car_repair, 'My Vehicle', () {}),
                _buildFeatureButton(Icons.chat, 'Communication', () {}),
              ],
            ),

            const SizedBox(height: 24),

            // === CURRENT SERVICE STATUS ===
            _buildStatusCard(
              title: 'Current Service Process Status',
              content: serviceStatus ?? 'No Appointment Made Yet...',
              backgroundColor: Colors.pink.shade50,
              icon: Icons.info_outline,
            ),

            const SizedBox(height: 12),

            // === UPCOMING APPOINTMENT ===
            _buildStatusCard(
              title: 'Upcoming Service Appointment',
              content: upcomingAppointment ?? 'No Appointment Made Yet...',
              backgroundColor: Colors.orange.shade50,
              icon: Icons.event_busy,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureButton(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: 100,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 30, color: Colors.deepPurple),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String content,
    required Color backgroundColor,
    required IconData icon,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28, color: Colors.deepPurple),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      content,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
