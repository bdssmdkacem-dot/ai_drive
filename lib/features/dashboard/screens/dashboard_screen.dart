import 'package:flutter/material.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/themes/app_theme.dart';
import '../../dashcam/screens/dashcam_screen.dart';
import '../../navigation/screens/navigation_screen.dart';
import '../../parking/screens/parking_screen.dart';
import '../../settings/screens/settings_screen.dart';
import 'trips_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;

  final _screens = const [
    _HomeTab(),
    NavigationScreen(embedded: true),
    DashcamScreen(embedded: true),
    ParkingScreen(embedded: true),
    TripsScreen(embedded: true),
    SettingsScreen(embedded: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _screens[_tab]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.navigation), label: 'Navigate'),
          BottomNavigationBarItem(icon: Icon(Icons.videocam), label: 'Dashcam'),
          BottomNavigationBarItem(icon: Icon(Icons.local_parking), label: 'Parking'),
          BottomNavigationBarItem(icon: Icon(Icons.route), label: 'Trips'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'AI Drive Assistant',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Everything runs on your device.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        _StartDriveCard(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.liveDriving),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _QuickTile(
              icon: Icons.videocam,
              label: 'Dashcam',
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.dashcam),
            ),
            _QuickTile(
              icon: Icons.local_parking,
              label: 'Parking Mode',
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.parking),
            ),
            _QuickTile(
              icon: Icons.remove_red_eye,
              label: 'Driver Monitor',
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.driverMonitor),
            ),
            _QuickTile(
              icon: Icons.directions_car,
              label: 'Vehicle',
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.vehicle),
            ),
          ],
        ),
      ],
    );
  }
}

class _StartDriveCard extends StatelessWidget {
  const _StartDriveCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.primary,
                child: Icon(Icons.play_arrow, color: Colors.black, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Start Driving',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      'Collision warnings, lane drift, driver monitoring & dashcam',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: AppTheme.primary),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
