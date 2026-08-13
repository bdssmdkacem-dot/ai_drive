import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/themes/app_theme.dart';

/// The app has no accounts / cloud sync in v1, so onboarding is just a
/// permissions walkthrough (camera, mic, location, notifications) rather
/// than a login flow.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _finish(BuildContext context) async {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.locationWhenInUse,
      Permission.notification,
      Permission.storage,
    ].request();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);

    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Text(
                'مساعد القيادة الذكي',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'AI Drive Assistant runs entirely on your phone — no account, '
                'no cloud upload. We need a few permissions to keep you safe '
                'on the road.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              const _PermissionRow(
                icon: Icons.camera_alt,
                title: 'Camera',
                subtitle: 'Road & driver-facing detection, dashcam recording',
              ),
              const _PermissionRow(
                icon: Icons.mic,
                title: 'Microphone',
                subtitle: 'Voice commands and dashcam audio',
              ),
              const _PermissionRow(
                icon: Icons.location_on,
                title: 'Location',
                subtitle: 'Navigation, speed, and trip logging',
              ),
              const _PermissionRow(
                icon: Icons.notifications_active,
                title: 'Notifications',
                subtitle: 'Parking-mode impact alerts',
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _finish(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
            child: Icon(icon, color: AppTheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  subtitle,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
